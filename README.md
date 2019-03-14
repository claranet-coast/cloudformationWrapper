Cloudformation bash wrapper
===========================

Bash script to wrap some cloudformation operation.
The script simplifies the process of creation, updating and deleting cloudformation stack ensuring the respect of some name convention.

# Prerequisities
* awscli installed and configured
* jq
* respect the name convention

# Convention
The script to work correctly needs that the template and parameters files complies a simple convention.

* Template file name: __"resource"."yaml"__
* Parameter file name: __"folder"/"resource"-parameters-"environment".json__

_resource, folder, yaml, environment_ can be configured using input parameters or bash variable.

# How to configure
The configuration is done setting the variable at the begining of the script or set them in console

* PROFILE: name of the aws-cli local profile
* PROJECT: name of the project. It is used in the stack name
* ENV: environment to use. It is used in the stack name and it must be included in parameters file name
* REGION: AWS region to use
* PARAMETERS_FOLDER: name of the folder where are located the parameters file
* TEMPLATE_EXTENSION: extension of the template file. (yaml, yml, template, json or your custom one)
* ENVIRONMENT_PARAMETER_NAME: name of the parameters inside the parameters file. If no parameter is preset it is not used in the stack name

# Example
### Folder tree
There are 3 template and the parameters in the folder with _parameters_ name
```
├── cfnwrapper.sh
├── rds.yaml
├── vpc.yaml
├── webapp.yaml
├── parameters
│   ├── rds-parameters-production.json
│   ├── rds-parameters-staging.json
│   ├── vpc-parameters-production.json
│   ├── vpc-parameters-staging.json
│   ├── webapp-parameters-production.json
│   └── webapp-parameters-staging.json
```
### Run command
Launching the command `./cfnwrapper.sh -o create -d -e staging vpc rds webapp` the script prints:
```
aws cloudformation create-stack --profile profile-name --stack-name project-name-staging-vpc --template-body file://vpc.yml --parameters file://parameters/vpc-parameters-staging.json --region eu-west-1 --capabilities CAPABILITY_NAMED_IAM
aws cloudformation create-stack --profile profile-name --stack-name project-name-staging-rds-v01 --template-body file://rds.yml --parameters file://parameters/rds-parameters-staging.json --region eu-west-1 --capabilities CAPABILITY_NAMED_IAM
aws cloudformation create-stack --profile profile-name --stack-name project-name-staging-webapp-v23 --template-body file://webapp.yml --parameters file://parameters/webapp-parameters-staging.json --region eu-west-1 --capabilities CAPABILITY_NAMED_IAM
```
Note the rds and webapp template have the ENVIRONMENT-PARAMETER-NAME and it is used in the stack name, vpc instead has no parameter and the stack name is without it.

Remove _-d_ (dry run) option the script launches the command and wait the stack is completed before launches the next one.

To pass variable from cli: `PROFILE=example ./cfnwrapper.sh -o create -e staging vpc rds webapp`