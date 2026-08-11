FROM python:3.12-alpine
WORKDIR /app
COPY serve.py .
ENV SERVICE_NAME=slash-api
ENV PORT=8080
EXPOSE 8080
CMD ["python", "serve.py"]
