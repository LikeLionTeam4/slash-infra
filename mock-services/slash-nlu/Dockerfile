FROM python:3.12-alpine
WORKDIR /app
COPY serve.py .
ENV SERVICE_NAME=slash-nlu
ENV PORT=8001
EXPOSE 8001
CMD ["python", "serve.py"]
