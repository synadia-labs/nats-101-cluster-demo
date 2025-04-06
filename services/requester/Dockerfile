# Use an official Python runtime as a parent image
FROM python:3.10-slim

# Set the working directory in the container
WORKDIR /app

# Copy the local files into the container
COPY . .

# Install the dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Set the default command to run the application
CMD ["python", "main.py"]