#!/bin/bash

# Variables
AZURE_SUBSCRIPTION_ID="<subscription_id>"
RESOURCE_GROUP="<resource_group>"
CONTAINER_APP_NAME="spring-petclinic"
LOCATION="<location>"
ACR_NAME="<container_registry_name>"
LOG_ANALYTICS_WORKSPACE="<log_analytics_workspace>"
PLACEHOLDER_IMAGE="mcr.microsoft.com/k8se/quickstart:latest"

# Generate a unique tag using the current timestamp
IMAGE_TAG=$(date +%Y%m%d%H%M%S)

# Create Resource Group
echo "Creating Resource Group..."
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create Log Analytics Workspace
echo "Creating Log Analytics Workspace..."
az monitor log-analytics workspace create \
  --resource-group $RESOURCE_GROUP \
  --workspace-name $LOG_ANALYTICS_WORKSPACE \
  --location $LOCATION

# Get Log Analytics Workspace ID
LOG_ANALYTICS_WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group $RESOURCE_GROUP \
  --workspace-name $LOG_ANALYTICS_WORKSPACE \
  --query customerId -o tsv)

# Create Azure Container Registry
echo "Creating Azure Container Registry..."
az acr create --resource-group $RESOURCE_GROUP --location $LOCATION --name $ACR_NAME --sku Basic

# Enable diagnostics for ACR
echo "Enabling diagnostics for Azure Container Registry..."
az monitor diagnostic-settings create \
  --resource $(az acr show --resource-group $RESOURCE_GROUP --name $ACR_NAME --query id -o tsv) \
  --resource-group $RESOURCE_GROUP \
  --workspace $LOG_ANALYTICS_WORKSPACE \
  --name "ACRDiagnostics" \
  --logs '[{"category": "ContainerRegistryLoginEvents", "enabled": true}, {"category": "ContainerRegistryRepositoryEvents", "enabled": true}]'

# Login to ACR, you will need the service principal that is running this to have ACR Push permissions
echo "Logging in to Azure Container Registry..."
az acr login --name $ACR_NAME --resource-group $RESOURCE_GROUP

# Build Docker image
echo "Building Docker image..."
docker build --platform linux/amd64 -t spring-petclinic .

# Tag Docker image
echo "Tagging Docker image..."
docker tag spring-petclinic $ACR_NAME.azurecr.io/spring-petclinic:$IMAGE_TAG

# Push Docker image to ACR
echo "Pushing Docker image to Azure Container Registry..."
docker push $ACR_NAME.azurecr.io/spring-petclinic:$IMAGE_TAG

# Create Azure Container App Environment
echo "Creating Azure Container App Environment..."
az containerapp env create \
  --name $CONTAINER_APP_NAME-env \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --logs-workspace-id $LOG_ANALYTICS_WORKSPACE_ID \
  --enable-workload-profiles false

# Deploy Container App
echo "Deploying Azure Container App..."
az containerapp create \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --environment $CONTAINER_APP_NAME-env \
  --ingress external \
  --target-port 8080 

# set the registry server adn turn on system-assigned manged identity
echo "Setting registry server and enabling system-assigned managed identity..."
az containerapp registry set --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --identity system \
  --server "$ACR_NAME.azurecr.io"

  # Get the Managed Identity Principal ID
MANAGED_IDENTITY_PRINCIPAL_ID=$(az containerapp show \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query identity.principalId -o tsv)

# Assign ACR Pull Role to Managed Identity
echo "Assigning ACR Pull Role to Managed Identity..."
ACR_ID=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query id -o tsv)
az role assignment create --assignee $MANAGED_IDENTITY_PRINCIPAL_ID --role "AcrPull" --scope $ACR_ID

# update the container app
echo "Updating Azure Container App..."
az containerapp update \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --image "$ACR_NAME.azurecr.io/spring-petclinic:$IMAGE_TAG" 

echo "Deployment to Azure Container Apps completed."
