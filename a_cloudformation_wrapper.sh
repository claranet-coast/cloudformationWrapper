#!/bin/bash

PROFILE=${PROFILE:-'profile-name'}
PROJECT=${PROJECT:-'project-name'}
ENV=${ENV:-'environment'}
REGION=${REGION:-'eu-west-1'}
PARAMETERS_FOLDER=${PARAMETERS_FOLDER:-'parameters'} # '.' if the same folder
TEMPLATE_EXTENSION=${TEMPLATE_EXTENSION:-'yml'} #or yml. Depends on your preference
ENVIRONMENT_PARAMETER_NAME=${ENVIRONMENT_PARAMETER_NAME:-'EnvironmentVersion'}
ALLOWED_ENVS="dev test int prod" # space separated list of allowed environment names

RESOURCE=()
OPERATION=''
DRY_RUN=false

print_help()
{
    cat << EOF
usage: $0 [-h] -o [create,update,changeset,validate] -e [Environment] -d resourcename1 resourcename2 ...

    This script create or update cloudformation script

    OPTIONS:
       -h      Show this message
       -e      Environment name
       -o      Operation to do. Allowed values [create, update, delete]
       -d      Dry run. Only print aws commands

 CONVENTIONS:
 This script assumes that the template and parameters file name have a specific format:
 Template: <resourcename>.<extension>
 Parameters: <resourcename>-parameters-<environment>.json

 This script create stack with this name:
 <project>-<environment>-<resourcename>

 Example:
 I have a template that create an rds for production environment for a project called github.
 Template name: rds.yaml
 Parameters name: rds-parameters-production.json
 After run this command: ./$0 -o create -e production rds
 the stack 'github-production-rds' will be created
EOF
}

create_stack(){
    for res in "${RESOURCE[@]}"
    do
        command="aws cloudformation \
        create-stack \
        --profile $PROFILE \
        --stack-name $(get_stack_name $res) \
        --template-body file://$res.$TEMPLATE_EXTENSION \
        --parameters file://$PARAMETERS_FOLDER/$res-parameters-$ENV.json \
        --region $REGION \
        --capabilities CAPABILITY_NAMED_IAM"
        echo $command
        if ! $DRY_RUN
        then
            $command

            aws cloudformation \
            wait stack-create-complete \
            --profile $PROFILE \
            --stack-name $(get_stack_name $res) \
            --region $REGION
            exit 0
        fi


    done
}

update_stack()
{
    for res in "${RESOURCE[@]}"
    do
        command="aws cloudformation \
        update-stack \
        --profile $PROFILE \
        --stack-name $(get_stack_name $res) \
        --template-body file://$res.$TEMPLATE_EXTENSION \
        --parameters file://$PARAMETERS_FOLDER/$res-parameters-$ENV.json \
        --region $REGION \
        --capabilities CAPABILITY_NAMED_IAM"
        echo $command
        if ! $DRY_RUN
        then
            $command

            aws cloudformation \
            wait stack-update-complete \
            --profile $PROFILE \
            --stack-name $(get_stack_name $res) \
            --region $REGION
            exit 0
        fi

    done
}

delete_stack()
{
    echo "Are you sure to delete stack? Type deleteme to continue"
    read confirmation_string
    if [[ $confirmation_string == 'deleteme' ]]
    then
        echo "Starting delete stack"
    else
        exit 1
    fi

    for res in "${RESOURCE[@]}"
    do
        command="aws cloudformation \
        delete-stack \
        --profile $PROFILE \
        --stack-name $(get_stack_name $res) \
        --region $REGION"
        echo $command
        if ! $DRY_RUN
        then
            $command

            aws cloudformation \
            wait stack-delete-complete \
            --profile $PROFILE \
            --stack-name $(get_stack_name $res) \
            --region $REGION
            exit 0
        fi

    done
}

create_changeset_stack()
{
    for res in "${RESOURCE[@]}"
    do
        command="aws cloudformation \
        create-change-set \
        --profile ${PROFILE_PREFIX} \
        --stack-name $(get_stack_name $res) \
        --template-body file://$res.$TEMPLATE_EXTENSION \
        --parameters file://$PARAMETERS_FOLDER/$res-parameters-$ENV.json \
        --region $REGION \
        --capabilities CAPABILITY_NAMED_IAM \
        --change-set-name $res-changeset"
        echo $command
        if ! $DRY_RUN
        then
            $command
        fi
    done
}

validate_stack()
{
    for res in "${RESOURCE[@]}"
    do
        command="aws cloudformation \
        validate-template \
        --profile ${PROFILE_PREFIX}-${ENV} \
        --region $REGION \
        --template-body file://$res.$TEMPLATE_EXTENSION"
        echo $command
        if ! $DRY_RUN
        then
            $command
        fi
    done
}

has_version()
{
    version=`cat $1 | jq --arg ENVIRONMENT_PARAMETER_NAME "$ENVIRONMENT_PARAMETER_NAME" '(.[] | select(.ParameterKey == $ENVIRONMENT_PARAMETER_NAME) | .ParameterValue)'|sed s/'"'//g`
    echo $version
}

get_stack_name()
{
    resource=$1
    version=$(has_version $PARAMETERS_FOLDER/$resource-parameters-$ENV.json)

    if [ $version ]
    then
        name=$PROJECT-$ENV-$resource-$version
    else
        name=$PROJECT-$ENV-$resource
    fi

    echo $name
}

############
### MAIN ###
############

while getopts "he:o:d" opt
do
     case $opt in
        h)
            print_help
            exit -1
            ;;
        e)
            ENV=$OPTARG
            ;;
        o)
            OPERATION=$OPTARG
            ;;
        d)
            DRY_RUN=true
            ;;
        ?)
            echo "Option/s error/s"
            print_help
            exit -1
            ;;
     esac
done
shift $(( OPTIND - 1 ))

if [[ -z $@ ]]
then
    echo
    echo "No resource provided, please add the resource you want to work with (e.g. pvc, rds...)"
    echo
    print_help
    exit -1
fi

for var in "$@"
do
  RESOURCE+=($var)
done


# Check if the environment passed as argument is allowed
if ! [[ $ALLOWED_ENVS =~ (^|[[:space:]])$ENV($|[[:space:]]) ]]
then
   echo "Invalid environment: Allowed values are [${ALLOWED_ENVS}]"
   print_help
   exit -1
fi

if [[ $OPERATION == 'create' ]]
then
    create_stack
elif [[ $OPERATION == 'update' ]]
then
    echo
    read -p "You are about to do an update stack and usually is a STUPID IDEA. You should consider doing a changeset. Do you want to do a changeset instead?[yY|nN]" -n 1 -r
    echo    # move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
        create_changeset_stack
    elif [[ $REPLY =~ ^[Nn]$ ]]
    then
        echo
        echo "Ok lets proceed with the update. If you break something you can only blame yourself."
        echo
        update_stack
    else
        echo "Unknown answer, just quitting."
    fi
elif [[ $OPERATION == 'changeset' ]]
then
    create_changeset_stack
elif [[ $OPERATION == 'validate' ]]
then
    validate_stack
elif [[ $OPERATION == 'delete' ]]
then
    delete_stack
else
    echo "Invalid operation $OPERATION: Allowed value are [create, update, delete]"
    print_help
fi
