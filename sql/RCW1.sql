--cw1 paymentService
--sql server, dist-6-505.uopnet.plymouth.ac.uk, schema RCW1

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'RCW1')
    EXEC('CREATE SCHEMA RCW1');
GO


--drops go first so i can rerun this while im still changing things.
--child tables before parents or the foreign keys block it
DROP TRIGGER IF EXISTS RCW1.trg_LogNewUser;
GO
DROP TRIGGER IF EXISTS RCW1.trg_LogNewSubscription;
GO
DROP VIEW IF EXISTS RCW1.vw_UserSubscription;
GO
DROP PROCEDURE IF EXISTS RCW1.usp_CreateSubscription;
DROP PROCEDURE IF EXISTS RCW1.usp_ReadSubscription;
DROP PROCEDURE IF EXISTS RCW1.usp_UpdateSubscription;
DROP PROCEDURE IF EXISTS RCW1.usp_DeleteSubscription;
GO
DROP TABLE IF EXISTS RCW1.SubscriptionLog;
DROP TABLE IF EXISTS RCW1.UserLog;
DROP TABLE IF EXISTS RCW1.Payment;
DROP TABLE IF EXISTS RCW1.Subscription;
DROP TABLE IF EXISTS RCW1.PlanFeature;
DROP TABLE IF EXISTS RCW1.Feature;
DROP TABLE IF EXISTS RCW1.[Plan];
DROP TABLE IF EXISTS RCW1.[User];
GO


--Se4, the tables

--user is a reserved word so it needs brackets. same with plan and role
CREATE TABLE RCW1.[User] (
    UserID       INT IDENTITY(1,1) PRIMARY KEY,
    Username     NVARCHAR(50)  NOT NULL UNIQUE,
    Email        NVARCHAR(255) NOT NULL UNIQUE,
    PasswordHash VARCHAR(255)  NOT NULL,   --bcrypt output is 60 chars, i had 30 at first which cut them in half
    [Role]       NVARCHAR(20)  NOT NULL DEFAULT 'User'
                 CHECK ([Role] IN ('User', 'Administrator'))
);
GO


CREATE TABLE RCW1.[Plan] (
    PlanID        INT IDENTITY(1,1) PRIMARY KEY,
    PlanName      NVARCHAR(50) NOT NULL UNIQUE,
    Price         DECIMAL(6,2) NOT NULL CHECK (Price >= 0),   --decimal not float, money shouldnt round
    BillingCycle  NVARCHAR(10) NOT NULL
                  CHECK (BillingCycle IN ('None', 'Monthly', 'Annual')),   --none covers the free plan
    [Description] NVARCHAR(255) NULL
);
GO


CREATE TABLE RCW1.Feature (
    FeatureID   INT IDENTITY(1,1) PRIMARY KEY,
    FeatureName NVARCHAR(100) NOT NULL UNIQUE
);
GO


--the linked entity out of my normalisation
CREATE TABLE RCW1.PlanFeature (
    PlanID    INT NOT NULL FOREIGN KEY REFERENCES RCW1.[Plan](PlanID) ON DELETE CASCADE,
    FeatureID INT NOT NULL FOREIGN KEY REFERENCES RCW1.Feature(FeatureID),
    PRIMARY KEY (PlanID, FeatureID)
);
GO


CREATE TABLE RCW1.Subscription (
    SubscriptionID     INT IDENTITY(1,1) PRIMARY KEY,
    UserID             INT NOT NULL FOREIGN KEY REFERENCES RCW1.[User](UserID) ON DELETE CASCADE,
    PlanID             INT NOT NULL FOREIGN KEY REFERENCES RCW1.[Plan](PlanID),
    StartDate          DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    EndDate            DATE NULL,
    SubscriptionStatus NVARCHAR(10) NOT NULL DEFAULT 'Active'
                       CHECK (SubscriptionStatus IN ('Active', 'Cancelled', 'Expired')),
    AutoRenew          BIT NOT NULL DEFAULT 1,
    CHECK (EndDate IS NULL OR EndDate >= StartDate)
);
--something i know is wrong with this: SubscriptionStatus is just a value that
--gets set, it doesnt change by itself when EndDate goes past. so a row can sit
--there saying Active with an end date from last year. fixing it properly needs
--a scheduled job or a computed column and i havent done that
GO


CREATE TABLE RCW1.Payment (
    PaymentID      INT IDENTITY(1,1) PRIMARY KEY,
    SubscriptionID INT NOT NULL FOREIGN KEY REFERENCES RCW1.Subscription(SubscriptionID) ON DELETE CASCADE,
    PaymentDate    DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    Amount         DECIMAL(6,2) NOT NULL CHECK (Amount > 0),
    PaymentMethod  NVARCHAR(20) NOT NULL
                   CHECK (PaymentMethod IN ('Card', 'PayPal', 'Apple Pay', 'Google Pay')),
                   --the method only, no card numbers. keeps this out of PCI DSS
    PaymentStatus  NVARCHAR(10) NOT NULL DEFAULT 'Completed'
                   CHECK (PaymentStatus IN ('Completed', 'Failed', 'Refunded'))
);
GO


CREATE TABLE RCW1.UserLog (
    LogID      INT IDENTITY(1,1) PRIMARY KEY,
    UserID     INT NULL FOREIGN KEY REFERENCES RCW1.[User](UserID) ON DELETE SET NULL,
    Username   NVARCHAR(50) NOT NULL,   --copied not joined, so the log still reads once the account goes
    Email      NVARCHAR(255) NOT NULL,
    [Role]     NVARCHAR(20) NOT NULL,
    DateLogged DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO


CREATE TABLE RCW1.SubscriptionLog (
    LogID          INT IDENTITY(1,1) PRIMARY KEY,
    SubscriptionID INT NULL FOREIGN KEY REFERENCES RCW1.Subscription(SubscriptionID) ON DELETE SET NULL,
    Username       NVARCHAR(50) NOT NULL,
    PlanName       NVARCHAR(50) NOT NULL,
    Price          DECIMAL(6,2) NOT NULL,
    DateLogged     DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO


--Se7, the triggers.
--these sit above the demo data on purpose. i had the inserts first and both log
--tables came out empty, because a trigger only fires on rows added after it
--exists. moving the inserts underneath fixed it

CREATE TRIGGER RCW1.trg_LogNewUser
ON RCW1.[User]
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO RCW1.UserLog (UserID, Username, Email, [Role])
    SELECT UserID, Username, Email, [Role] FROM inserted;
END;
GO


CREATE TRIGGER RCW1.trg_LogNewSubscription
ON RCW1.Subscription
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO RCW1.SubscriptionLog (SubscriptionID, Username, PlanName, Price)
    SELECT i.SubscriptionID, u.Username, p.PlanName, p.Price
    FROM inserted i
        JOIN RCW1.[User] u ON u.UserID = i.UserID
        JOIN RCW1.[Plan] p ON p.PlanID = i.PlanID;
END;
GO
--first go at this used variables and SELECT @x = ... from inserted. it was fine
--for one row and quietly logged only the last one when several went in together,
--so it had to become a plain insert straight off inserted


--Se5, the view
CREATE VIEW RCW1.vw_UserSubscription
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
    s.EndDate,
    s.SubscriptionStatus
FROM RCW1.Subscription s
    JOIN RCW1.[User] u ON u.UserID = s.UserID
    JOIN RCW1.[Plan] p ON p.PlanID = s.PlanID;
GO


--Se6, crud on Subscription

CREATE PROCEDURE RCW1.usp_CreateSubscription
    @UserID INT,
    @PlanID INT,
    @StartDate DATE = NULL,
    @AutoRenew BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO RCW1.Subscription (UserID, PlanID, StartDate, AutoRenew)
    VALUES (@UserID, @PlanID, ISNULL(@StartDate, CAST(GETDATE() AS DATE)), @AutoRenew);

    SELECT SCOPE_IDENTITY() AS NewSubscriptionID;
END;
GO


CREATE PROCEDURE RCW1.usp_ReadSubscription
    @SubscriptionID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    --goes through the view so this and the view cant drift apart
    SELECT * FROM RCW1.vw_UserSubscription
    WHERE @SubscriptionID IS NULL OR SubscriptionID = @SubscriptionID;
END;
GO


CREATE PROCEDURE RCW1.usp_UpdateSubscription
    @SubscriptionID INT,
    @PlanID INT = NULL,
    @SubscriptionStatus NVARCHAR(10) = NULL,
    @EndDate DATE = NULL,
    @AutoRenew BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    --ISNULL keeps whats already there when a parameter isnt passed. my first
    --version set every column and wiped the ones i left out
    UPDATE RCW1.Subscription
    SET PlanID             = ISNULL(@PlanID, PlanID),
        SubscriptionStatus = ISNULL(@SubscriptionStatus, SubscriptionStatus),
        EndDate            = ISNULL(@EndDate, EndDate),
        AutoRenew          = ISNULL(@AutoRenew, AutoRenew)
    WHERE SubscriptionID = @SubscriptionID;

    SELECT @@ROWCOUNT AS RowsUpdated;   --0 means the id wasnt there
END;
GO


CREATE PROCEDURE RCW1.usp_DeleteSubscription
    @SubscriptionID INT
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM RCW1.Subscription WHERE SubscriptionID = @SubscriptionID;

    SELECT @@ROWCOUNT AS RowsDeleted;
END;
GO


--demo data

INSERT INTO RCW1.[Plan] (PlanName, Price, BillingCycle, [Description])
VALUES ('Free', 0.00,  'None',   'Trail search and route recording.'),
       ('Plus', 35.99, 'Annual', 'Offline maps and trail conditions.'),
       ('Peak', 79.99, 'Annual', 'Plus, with route planning and alerts.');
GO

--names off the alltrails compare plans page
INSERT INTO RCW1.Feature (FeatureName)
VALUES ('Trail search'), ('Route recording'), ('Offline Maps'),
       ('Trail Conditions'), ('Live Share'), ('Wrong-Turn Alerts');
GO

INSERT INTO RCW1.PlanFeature (PlanID, FeatureID)
VALUES (1,1), (1,2),
       (2,1), (2,2), (2,3), (2,4),
       (3,1), (3,2), (3,3), (3,4), (3,5), (3,6);
GO

--the accounts from Table 1. the hash strings are real bcrypt output for the
--passwords in the brief made in python not text i typed
INSERT INTO RCW1.[User] (Username, Email, PasswordHash, [Role])
VALUES ('Grace Hopper',    'grace@plymouth.ac.uk', '$2b$12$G7Jsfmv8P0zbE7n5Evkn8OCiopYWyrexY6oKDiROLwwPqtMMBUkOW', 'Administrator'),
       ('Tim Berners-Lee', 'tim@plymouth.ac.uk',   '$2b$12$7Ohkj39OZSuUQqC6kxy.7uEeTK1pQxI54/s3/phLQ9ehSNdJO0b6G', 'User'),
       ('Ada Lovelace',    'ada@plymouth.ac.uk',   '$2b$12$hqSvXHifwwE/DlQ/7ClmYOTEhWtCdyk3NcC22HdI64UHoCRhEPah6', 'User');
GO

INSERT INTO RCW1.Subscription (UserID, PlanID, StartDate, EndDate, SubscriptionStatus)
VALUES (1, 3, '2026-01-15', '2027-01-15', 'Active'),
       (2, 2, '2025-06-01', '2026-06-01', 'Active'),
       (3, 1, '2025-03-10', '2026-07-01', 'Cancelled');
GO

--nothing charged against the free plan
INSERT INTO RCW1.Payment (SubscriptionID, PaymentDate, Amount, PaymentMethod, PaymentStatus)
VALUES (1, '2026-01-22 09:14:22', 79.99, 'Card',   'Completed'),
       (2, '2025-06-08 11:02:47', 35.99, 'PayPal', 'Completed'),
       (2, '2026-06-08 11:04:10', 35.99, 'PayPal', 'Failed');
GO


--everything has rows in it

SELECT * FROM RCW1.[User];
SELECT * FROM RCW1.[Plan];
SELECT * FROM RCW1.Feature;
SELECT * FROM RCW1.PlanFeature;
SELECT * FROM RCW1.Subscription;
SELECT * FROM RCW1.Payment;
SELECT * FROM RCW1.UserLog;
SELECT * FROM RCW1.SubscriptionLog;
GO

SELECT * FROM RCW1.vw_UserSubscription;
GO


--testing

--duplicate username, 2627
-- INSERT INTO RCW1.[User] (Username, Email, PasswordHash)
-- VALUES ('Grace Hopper', 'another@plymouth.ac.uk', 'hash');

--a status thats not one of the three, 547
-- INSERT INTO RCW1.Subscription (UserID, PlanID, SubscriptionStatus)
-- VALUES (1, 2, 'Paused');

--subscription for a user that doesnt exist, 547
-- INSERT INTO RCW1.Subscription (UserID, PlanID) VALUES (999, 1);

--cant delete a plan someone is on, 547
-- DELETE FROM RCW1.[Plan] WHERE PlanID = 2;

--the user trigger, run all three lines together
-- SELECT * FROM RCW1.UserLog;
-- INSERT INTO RCW1.[User] (Username, Email, PasswordHash) VALUES ('Test User', 'test@plymouth.ac.uk', 'hash');
-- SELECT * FROM RCW1.UserLog;

--cascade. subscription 2 has payments on it so they should go too, and the
--last line shows the log row survived with a null id
-- SELECT * FROM RCW1.Payment WHERE SubscriptionID = 2;
-- DELETE FROM RCW1.Subscription WHERE SubscriptionID = 2;
-- SELECT * FROM RCW1.Payment WHERE SubscriptionID = 2;
-- SELECT * FROM RCW1.SubscriptionLog WHERE SubscriptionID IS NULL;

--the procedures
-- EXEC RCW1.usp_ReadSubscription;
-- EXEC RCW1.usp_CreateSubscription @UserID = 1, @PlanID = 2;
-- EXEC RCW1.usp_UpdateSubscription @SubscriptionID = 1, @SubscriptionStatus = 'Cancelled';
-- EXEC RCW1.usp_DeleteSubscription @SubscriptionID = 3;
-- EXEC RCW1.usp_ReadSubscription;