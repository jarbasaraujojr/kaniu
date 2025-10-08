# Use uma imagem Python leve como base
FROM python:3.12-slim

# Defina o diretório de trabalho no contêiner
WORKDIR /app

# Copie o arquivo de dependências e instale as bibliotecas
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copie todo o código da sua aplicação para o contêiner
COPY . .

# Exponha a porta que a sua aplicação vai usar
EXPOSE 8001

# Comando para iniciar o servidor uvicorn
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8001"]
