# pull official base image
FROM public.ecr.aws/docker/library/node:alpine

# set working directory
WORKDIR /app

# add `/app/node_modules/.bin` to $PATH
ENV PATH /app/node_modules/.bin:$PATH

# install app dependencies
COPY package.json ./
COPY package-lock.json ./
RUN sudo yum install -y yum-utils
RUN sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
RUN sudo yum -y install terraform
RUN npm install --silent
RUN npm install react-scripts@3.4.1 -g --silent

# add app
COPY . ./

# Make port 3000 available to the world outside this container
# Using 8080 since that's what we had in API Gateway
EXPOSE 8080

# start app
CMD ["npm", "start"]
