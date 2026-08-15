FROM node:22.14.0-alpine

WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev --ignore-scripts
COPY app.js worker.js ./

USER node
EXPOSE 3000
CMD ["npm", "start"]
