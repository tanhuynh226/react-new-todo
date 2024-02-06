# pull official base image
FROM node:alpine

# set working directory
WORKDIR /app

# add `/app/node_modules/.bin` to $PATH
ENV PATH /app/node_modules/.bin:$PATH

# install app dependencies
COPY package.json ./
COPY package-lock.json ./
RUN npm install
RUN npm install react-scripts@3.4.1 -g

# add app
COPY . ./

# Make port 3000 available to the world outside this container
# Using 8080 since that's what we had in API Gateway
EXPOSE 8080

# start app
CMD ["npm", "start"]