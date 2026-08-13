FROM python:3.12-slim

# pyodbc needs microsoft's odbc driver
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gnupg unixodbc-dev g++ \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" \
    > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y msodbcsql17 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# requirements go in on their own first so docker caches the pip layer and
# doesnt reinstall everything each time i change a python file
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

# same command as running it locally, so the container behaves the same way
CMD ["python", "app.py"]
