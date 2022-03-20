# Devops Exercise Solutions

## Stage 0 - Preparing your environment:

1. The kubernetes solution I'm using is Docker Desktop Kubernetes. You can install it _[here](https://www.docker.com/products/docker-desktop/)_.
2. While docker desktop is downloading and installing, create a _[docker hub account](https://hub.docker.com/signup)_ (You're going to need it when it's time to push your image to docker hub).
3. When docker desktop is done installing - luanch it and sign in with the docker hub account you've just opened.

    _**Make sure to enable Kubernetes in the settings**_
4. **(Optional)** Install a version control management system - In this case I'm using _[git](https://git-scm.com/downloads)_
5. Clone the exercise onto your local machine (if you've skipped step 4, just download the repo):
    ```bash
    git clone https://gitlab.com/iyehuda/devops-exercise.git
    ```
6. Install an IDE - I recommend _[VS Code](https://code.visualstudio.com/download)_ since it has an official microsoft docker extension that makes life a whole lot easier.
7. Install the docker extension: `ms-azuretools.vscode-docker`

Now your environment should be ready for the exercise.

## Stage 1 - Application Deployment
### Step 1 - Building the docker image and pushing it to docker hub:

1. Open the repo you have cloned in VS Code. 
2. Right-Click the `Dockerfile` 
3. Select `Build Image...`
    
    **Note:** The image name will be the same as the folder you've opened - in this case the folder's name is `devopsexercise` since that's the name of the repo we've cloned. If you have downloaded the repo manually it might be different for you.
4. As the build is running - create a repository in docker hub named `coin-master-api`.
5. After the build has finished - View the image in the docker desktop UI under Images > Local.
    
    The current name of the image is `devopsexercise:latest`.
    Before we push it onto docker hub we would like to change the name, since the Makefile is built to work with the image name `coin-master-api:latest`.
    
    To change the name run the following command:
    ```
    docker tag devopsexcercise:latest <Your dockerhub namespace>/coin-master-api:latest
    ```
6. Push the image onto your new repository:
    ```docker
    docker push <Your dockerhub namespace>/coin-master-api:latest
    ```
## Step 2 - Deploy a Kubernetes Cluster

We have chosen docker for desktop in stage 0.

## Step 3 - Deploy a workload on the Kubernetes cluster