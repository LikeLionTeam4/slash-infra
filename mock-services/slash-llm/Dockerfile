FROM python:3.12-alpine
WORKDIR /app
COPY serve.py .
ENV SERVICE_NAME=slash-llm
ENV PORT=8000
EXPOSE 8000
CMD ["python", "serve.py"]
