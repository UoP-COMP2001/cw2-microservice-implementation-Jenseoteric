--cw2 paymentService
--sql server, dist-6-505.uopnet.plymouth.ac.uk, schema RCW2

--same design as cw1 with the bits the microservice actually needed added on.
--TrialEndDate, because the compare plans page gives seven days free before it
--charges you, and a revenue view and refund procedure for the two admin stories
--in the backlog

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'RCW2')
    EXEC('CREATE SCHEMA RCW2');
GO


DROP TRIGGER IF EXISTS RCW2.trg_LogNewUser;
GO
DROP TRIGGER IF EXISTS RCW2.trg_LogNewSubscription;
GO
DROP VIEW IF EXISTS RCW2.vw_UserSubscription;
GO
DROP VIEW IF EXISTS RCW2.vw_RevenueByPlan;
GO
DROP PROCEDURE IF EXISTS RCW2.usp_CreateSubscription;
DROP PROCEDURE IF EXISTS RCW2.usp_ReadSubscription;
DROP PROCEDURE IF EXISTS RCW2.usp_UpdateSubscription;
DROP PROCEDURE IF EXISTS RCW2.usp_DeleteSubscription;
DROP PROCEDURE IF EXISTS RCW2.usp_RefundPayment;
GO
DROP TABLE IF EXISTS RCW2.SubscriptionLog;
DROP TABLE IF EXISTS RCW2.UserLog;
DROP TABLE IF EXISTS RCW2.Payment;
DROP TABLE IF EXISTS RCW2.Subscription;
DROP TABLE IF EXISTS RCW2.PlanFeature;
DROP TABLE IF EXISTS RCW2.Feature;
DROP TABLE IF EXISTS RCW2.[Plan];
DROP TABLE IF EXISTS RCW2.[User];
GO


--tables

CREATE TABLE RCW2.[User] (
    UserID       INT IDENTITY(1,1) PRIMARY KEY,
    Username     NVARCHAR(50)  NOT NULL UNIQUE,
    Email        NVARCHAR(255) NOT NULL UNIQUE,
    PasswordHash VARCHAR(255)  NOT NULL,   --bcrypt output is 60 chars
    [Role]       NVARCHAR(20)  NOT NULL DEFAULT 'User'
                 CHECK ([Role] IN ('User', 'Administrator'))
);
GO


CREATE TABLE RCW2.[Plan] (
    PlanID        INT IDENTITY(1,1) PRIMARY KEY,
    PlanName      NVARCHAR(50) NOT NULL UNIQUE,
    Price         DECIMAL(6,2) NOT NULL CHECK (Price >= 0),
    BillingCycle  NVARCHAR(10) NOT NULL
                  CHECK (BillingCycle IN ('None', 'Monthly', 'Annual')),
    [Description] NVARCHAR(255) NULL
);
GO


CREATE TABLE RCW2.Feature (
    FeatureID   INT IDENTITY(1,1) PRIMARY KEY,
    FeatureName NVARCHAR(100) NOT NULL UNIQUE
);
GO


CREATE TABLE RCW2.PlanFeature (
    PlanID    INT NOT NULL FOREIGN KEY REFERENCES RCW2.[Plan](PlanID) ON DELETE CASCADE,
    FeatureID INT NOT NULL FOREIGN KEY REFERENCES RCW2.Feature(FeatureID),
    PRIMARY KEY (PlanID, FeatureID)
);
GO


CREATE TABLE RCW2.Subscription (
    SubscriptionID     INT IDENTITY(1,1) PRIMARY KEY,
    UserID             INT NOT NULL FOREIGN KEY REFERENCES RCW2.[User](UserID) ON DELETE CASCADE,
    PlanID             INT NOT NULL FOREIGN KEY REFERENCES RCW2.[Plan](PlanID),
    StartDate          DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    TrialEndDate       DATE NULL,   --null on the free plan, nothing to charge for
    EndDate            DATE NULL,
    SubscriptionStatus NVARCHAR(10) NOT NULL DEFAULT 'Active'
                       CHECK (SubscriptionStatus IN ('Active', 'Cancelled', 'Expired')),
    AutoRenew          BIT NOT NULL DEFAULT 1,
    CHECK (EndDate IS NULL OR EndDate >= StartDate),
    CHECK (TrialEndDate IS NULL OR TrialEndDate >= StartDate)
);
--same limitation as cw1, SubscriptionStatus is set by hand and doesnt move to
--Expired on its own when EndDate passes
GO


CREATE TABLE RCW2.Payment (
    PaymentID      INT IDENTITY(1,1) PRIMARY KEY,
    SubscriptionID INT NOT NULL FOREIGN KEY REFERENCES RCW2.Subscription(SubscriptionID) ON DELETE CASCADE,
    PaymentDate    DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    Amount         DECIMAL(6,2) NOT NULL CHECK (Amount > 0),
    PaymentMethod  NVARCHAR(20) NOT NULL
                   CHECK (PaymentMethod IN ('Card', 'PayPal', 'Apple Pay', 'Google Pay')),
                   --the method only, no card numbers. keeps this out of PCI DSS
    PaymentStatus  NVARCHAR(10) NOT NULL DEFAULT 'Completed'
                   CHECK (PaymentStatus IN ('Completed', 'Failed', 'Refunded'))
);
GO


CREATE TABLE RCW2.UserLog (
    LogID      INT IDENTITY(1,1) PRIMARY KEY,
    UserID     INT NULL FOREIGN KEY REFERENCES RCW2.[User](UserID) ON DELETE SET NULL,
    Username   NVARCHAR(50) NOT NULL,
    Email      NVARCHAR(255) NOT NULL,
    [Role]     NVARCHAR(20) NOT NULL,
    DateLogged DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO


CREATE TABLE RCW2.SubscriptionLog (
    LogID          INT IDENTITY(1,1) PRIMARY KEY,
    SubscriptionID INT NULL FOREIGN KEY REFERENCES RCW2.Subscription(SubscriptionID) ON DELETE SET NULL,
    Username       NVARCHAR(50) NOT NULL,
    PlanName       NVARCHAR(50) NOT NULL,
    Price          DECIMAL(6,2) NOT NULL,
    DateLogged     DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO


--triggers, above the demo data so they actually fire on it

CREATE TRIGGER RCW2.trg_LogNewUser
ON RCW2.[User]
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO RCW2.UserLog (UserID, Username, Email, [Role])
    SELECT UserID, Username, Email, [Role] FROM inserted;
END;
GO


CREATE TRIGGER RCW2.trg_LogNewSubscription
ON RCW2.Subscription
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO RCW2.SubscriptionLog (SubscriptionID, Username, PlanName, Price)
    SELECT i.SubscriptionID, u.Username, p.PlanName, p.Price
    FROM inserted i
        JOIN RCW2.[User] u ON u.UserID = i.UserID
        JOIN RCW2.[Plan] p ON p.PlanID = i.PlanID;
END;
GO
--this one matters more here than in cw1, because the api creates subscriptions.
--if the log fills up after a POST then the trigger is firing through the
--microservice and not just through sql i typed myself


--views

CREATE VIEW RCW2.vw_UserSubscription
AS
SELECT
    u.UserID,
    u.Username,
    u.Email,
    p.PlanName,
    p.Price,
    p.BillingCycle,
    s.SubscriptionID,
    s.StartDate,
    s.TrialEndDate,
    s.EndDate,
    s.SubscriptionStatus
FROM RCW2.Subscription s
    JOIN RCW2.[User] u ON u.UserID = s.UserID
    JOIN RCW2.[Plan] p ON p.PlanID = s.PlanID;
GO


--for the admin story about tracking business performance.
--refunded and failed payments are left out of the total, only money that
--actually came in counts
CREATE VIEW RCW2.vw_RevenueByPlan
AS
SELECT
    p.PlanName,
    p.BillingCycle,
    COUNT(pay.PaymentID) AS PaymentsTaken,
    SUM(pay.Amount)      AS TotalRevenue
FROM RCW2.Payment pay
    JOIN RCW2.Subscription s ON s.SubscriptionID = pay.SubscriptionID
    JOIN RCW2.[Plan] p       ON p.PlanID = s.PlanID
WHERE pay.PaymentStatus = 'Completed'
GROUP BY p.PlanName, p.BillingCycle;
GO


--crud on Subscription

CREATE PROCEDURE RCW2.usp_CreateSubscription
    @UserID INT,
    @PlanID INT,
    @StartDate DATE = NULL,
    @TrialEndDate DATE = NULL,
    @AutoRenew BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO RCW2.Subscription (UserID, PlanID, StartDate, TrialEndDate, AutoRenew)
    VALUES (@UserID, @PlanID, ISNULL(@StartDate, CAST(GETDATE() AS DATE)), @TrialEndDate, @AutoRenew);

    SELECT SCOPE_IDENTITY() AS NewSubscriptionID;
END;
GO


CREATE PROCEDURE RCW2.usp_ReadSubscription
    @SubscriptionID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT * FROM RCW2.vw_UserSubscription
    WHERE @SubscriptionID IS NULL OR SubscriptionID = @SubscriptionID;
END;
GO


CREATE PROCEDURE RCW2.usp_UpdateSubscription
    @SubscriptionID INT,
    @PlanID INT = NULL,
    @SubscriptionStatus NVARCHAR(10) = NULL,
    @EndDate DATE = NULL,
    @TrialEndDate DATE = NULL,
    @AutoRenew BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE RCW2.Subscription
    SET PlanID             = ISNULL(@PlanID, PlanID),
        SubscriptionStatus = ISNULL(@SubscriptionStatus, SubscriptionStatus),
        EndDate            = ISNULL(@EndDate, EndDate),
        TrialEndDate       = ISNULL(@TrialEndDate, TrialEndDate),
        AutoRenew          = ISNULL(@AutoRenew, AutoRenew)
    WHERE SubscriptionID = @SubscriptionID;

    SELECT @@ROWCOUNT AS RowsUpdated;
END;
GO


CREATE PROCEDURE RCW2.usp_DeleteSubscription
    @SubscriptionID INT
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM RCW2.Subscription WHERE SubscriptionID = @SubscriptionID;

    SELECT @@ROWCOUNT AS RowsDeleted;
END;
GO

CREATE PROCEDURE RCW2.usp_RefundPayment
    @PaymentID INT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE RCW2.Payment
    SET PaymentStatus = 'Refunded'
    WHERE PaymentID = @PaymentID AND PaymentStatus = 'Completed';
    --the second condition stops a failed payment being refunded, since nothing
    --was taken in the first place

    SELECT @@ROWCOUNT AS RowsRefunded;
END;
GO


--demo data

INSERT INTO RCW2.[Plan] (PlanName, Price, BillingCycle, [Description])
VALUES ('Free', 0.00,  'None',   'Trail search and route recording.'),
       ('Plus', 35.99, 'Annual', 'Offline maps and trail conditions.'),
       ('Peak', 79.99, 'Annual', 'Plus, with route planning and alerts.');
GO

INSERT INTO RCW2.Feature (FeatureName)
VALUES ('Trail search'), ('Route recording'), ('Offline Maps'),
       ('Trail Conditions'), ('Live Share'), ('Wrong-Turn Alerts');
GO

INSERT INTO RCW2.PlanFeature (PlanID, FeatureID)
VALUES (1,1), (1,2),
       (2,1), (2,2), (2,3), (2,4),
       (3,1), (3,2), (3,3), (3,4), (3,5), (3,6);
GO

--the accounts from Table 1. the hash strings are real bcrypt output for the
--passwords in the brief, made in python, not text i typed
INSERT INTO RCW2.[User] (Username, Email, PasswordHash, [Role])
VALUES ('Grace Hopper',    'grace@plymouth.ac.uk', '$2b$12$G7Jsfmv8P0zbE7n5Evkn8OCiopYWyrexY6oKDiROLwwPqtMMBUkOW', 'Administrator'),
       ('Tim Berners-Lee', 'tim@plymouth.ac.uk',   '$2b$12$7Ohkj39OZSuUQqC6kxy.7uEeTK1pQxI54/s3/phLQ9ehSNdJO0b6G', 'User'),
       ('Ada Lovelace',    'ada@plymouth.ac.uk',   '$2b$12$hqSvXHifwwE/DlQ/7ClmYOTEhWtCdyk3NcC22HdI64UHoCRhEPah6', 'User');
GO

INSERT INTO RCW2.Subscription (UserID, PlanID, StartDate, TrialEndDate, EndDate, SubscriptionStatus)
VALUES (1, 3, '2026-01-15', '2026-01-22', '2027-01-15', 'Active'),
       (2, 2, '2025-06-01', '2025-06-08', '2026-06-01', 'Active'),
       (3, 1, '2025-03-10', NULL,         '2026-07-01', 'Cancelled');
GO

--nothing charged against the free plan, and nothing taken until a trial ends
INSERT INTO RCW2.Payment (SubscriptionID, PaymentDate, Amount, PaymentMethod, PaymentStatus)
VALUES (1, '2026-01-22 09:14:22', 79.99, 'Card',   'Completed'),
       (2, '2025-06-08 11:02:47', 35.99, 'PayPal', 'Completed'),
       (2, '2026-06-08 11:04:10', 35.99, 'PayPal', 'Failed');
GO


--everything has rows in it

SELECT * FROM RCW2.[User];
SELECT * FROM RCW2.[Plan];
SELECT * FROM RCW2.Feature;
SELECT * FROM RCW2.PlanFeature;
SELECT * FROM RCW2.Subscription;
SELECT * FROM RCW2.Payment;
SELECT * FROM RCW2.UserLog;
SELECT * FROM RCW2.SubscriptionLog;
GO

SELECT * FROM RCW2.vw_UserSubscription;
SELECT * FROM RCW2.vw_RevenueByPlan;
GO

--SELECT * FROM RCW2.SubscriptionLog;

--testing

--duplicate username, 2627
-- INSERT INTO RCW2.[User] (Username, Email, PasswordHash)
-- VALUES ('Grace Hopper', 'another@plymouth.ac.uk', 'hash');

--a status thats not one of the three, 547
-- INSERT INTO RCW2.Subscription (UserID, PlanID, SubscriptionStatus)
-- VALUES (1, 2, 'Paused');

--negative payment, 547
-- INSERT INTO RCW2.Payment (SubscriptionID, Amount, PaymentMethod)
-- VALUES (1, -10.00, 'Card');

--cant delete a plan someone is on, 547
-- DELETE FROM RCW2.[Plan] WHERE PlanID = 2;

--the user trigger, run all three lines together
-- SELECT * FROM RCW2.UserLog;
-- INSERT INTO RCW2.[User] (Username, Email, PasswordHash) VALUES ('Test User', 'test@plymouth.ac.uk', 'hash');
-- SELECT * FROM RCW2.UserLog;

--refund. payment 1 is Completed so it changes, payment 3 is Failed so it wont
-- SELECT * FROM RCW2.Payment WHERE PaymentID IN (1, 3);
-- EXEC RCW2.usp_RefundPayment @PaymentID = 1;
-- EXEC RCW2.usp_RefundPayment @PaymentID = 3;
-- SELECT * FROM RCW2.Payment WHERE PaymentID IN (1, 3);
-- SELECT * FROM RCW2.vw_RevenueByPlan;

--cascade. subscription 2 has payments on it so they should go too, and the
--last line shows the log row survived with a null id
-- SELECT * FROM RCW2.Payment WHERE SubscriptionID = 2;
-- DELETE FROM RCW2.Subscription WHERE SubscriptionID = 2;
-- SELECT * FROM RCW2.Payment WHERE SubscriptionID = 2;
-- SELECT * FROM RCW2.SubscriptionLog WHERE SubscriptionID IS NULL;

--the procedures
-- EXEC RCW2.usp_ReadSubscription;
-- EXEC RCW2.usp_CreateSubscription @UserID = 1, @PlanID = 2;
-- EXEC RCW2.usp_UpdateSubscription @SubscriptionID = 1, @SubscriptionStatus = 'Cancelled';
-- EXEC RCW2.usp_DeleteSubscription @SubscriptionID = 3;
-- EXEC RCW2.usp_ReadSubscription;