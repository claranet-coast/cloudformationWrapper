#!/bin/bash

## Script Version ####
SCRIPT_VERSION="1.1" #
######################

set -e

PROFILE=${PROFILE:-'profile-name'}
PROJECT=${PROJECT:-'project-name'}
ENV=${ENV:-'environment'}
REGION=${REGION:-'eu-west-1'}
SERVICE=${SERVICE:-'common'}
PARAMETERS_FOLDER=${PARAMETERS_FOLDER:-'parameters'} # '.' if the same folder
TEMPLATE_FOLDER=${TEMPLATE_FOLDER:-'.'}
TEMPLATE_EXTENSION=${TEMPLATE_EXTENSION:-'yml'} #or yml. Depends on your preference
ENVIRONMENT_PARAMETER_NAME=${ENVIRONMENT_PARAMETER_NAME:-'EnvironmentVersion'}
ALLOWED_ENVS="dev test int prd" # space separated list of allowed environment names

RESOURCE=()
OPERATION=''
DRY_RUN=false
INSANEMODE=false # Set to true if you're not using git

print_help()
{
    cat << EOF
usage: $0 [-h] -o [create,update,delete,changeset,validate,status] -e [Environment] -d resourcename1 resourcename2 ...

    This script create or update cloudformation script

    OPTIONS:
       -h      Show this message
       -e      Environment name
       -o      Operation to do. Allowed values [create, update, changeset, delete, validate, status]
       -d      Dry run. Only print aws commands
       -f      Force the execution of CFN even if local repo is behind the default remote one. Ignored if -d
       -s      Service name to use


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

$0: Version: $SCRIPT_VERSION. For more details see the project page https://github.com/claranet-coast/cloudformationWrapper

EOF
}

print_version()
{
    echo $SCRIPT_VERSION
}

create_stack(){
    for res in "${RESOURCE[@]}"
    do
        command="aws cloudformation \
        create-stack \
        --profile $PROFILE \
        --stack-name $(get_stack_name $res) \
        --template-body file://$TEMPLATE_FOLDER/$res.$TEMPLATE_EXTENSION \
        --parameters file://$PARAMETERS_FOLDER/${SERVICE}-$ENV-$res.json \
        --region $REGION \
        --enable-termination-protection \
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
        --template-body file://$TEMPLATE_FOLDER/$res.$TEMPLATE_EXTENSION \
        --parameters file://$PARAMETERS_FOLDER/${SERVICE}-$ENV-$res.json \
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
    echo "Are you sure to delete stack? (Type deleteme to continue)"
    read confirmation_string
    if [[ $confirmation_string != 'deleteme' ]]
    then
        exit 1
    fi

    for res in "${RESOURCE[@]}"
    do
        stack_name=$(get_stack_name $res)
        delete_command="aws cloudformation \
        delete-stack \
        --profile $PROFILE \
        --stack-name $stack_name \
        --region $REGION"
        if ! $DRY_RUN
        then
            check_termination_protection_command="aws cloudformation \
            describe-stacks \
            --profile $PROFILE \
            --stack-name $stack_name \
            --query Stacks[0].EnableTerminationProtection \
            --output json \
            --region $REGION"
            echo $check_termination_protection_command
            echo "Checking termination protection:"
            if [[ $($check_termination_protection_command) == 'true' ]]
            then
                echo "The stack has termination protection enabled, do you still want to continue? (Type yes to continue)"
                read tp_confirmation_string
                if [[ $tp_confirmation_string == 'yes' ]]
                then
                    disable_termination_protection_command="aws cloudformation \
                    update-termination-protection \
                    --no-enable-termination-protection \
                    --profile $PROFILE \
                    --stack-name $stack_name \
                    --region $REGION"
                    echo $disable_termination_protection_command
                    echo "Disabling termination protection:"
                    $disable_termination_protection_command
                else
                    exit 1
                fi
            fi
            
            echo $delete_command
            echo "Starting stack delete:"
            $delete_command

            aws cloudformation \
            wait stack-delete-complete \
            --profile $PROFILE \
            --stack-name $stack_name \
            --region $REGION
            exit 0
        else
            echo $delete_command
        fi

    done
}

create_changeset_stack()
{
    for res in "${RESOURCE[@]}"
    do
        command="aws cloudformation \
        create-change-set \
        --profile ${PROFILE} \
        --stack-name $(get_stack_name $res) \
        --template-body file://$TEMPLATE_FOLDER/$res.$TEMPLATE_EXTENSION \
        --parameters file://$PARAMETERS_FOLDER/${SERVICE}-$ENV-$res.json \
        --region $REGION \
        --capabilities CAPABILITY_NAMED_IAM \
        --change-set-name $res-changeset"
        echo $command
        if ! $DRY_RUN
        then
            echo -e "\nCreating Changeset:\n"
            $command
            # Wait until the changeset creation completes
            aws cloudformation wait change-set-create-complete \
              --change-set-name $res-changeset \
              --profile ${PROFILE} \
              --region $REGION \
              --stack-name $(get_stack_name $res)
            # Describe the changeset
            echo -e "\nDescribe Changeset:\n"
            describe=$(aws cloudformation describe-change-set \
              --change-set-name $res-changeset \
              --profile ${PROFILE} \
              --region $REGION \
              --output json \
              --stack-name $(get_stack_name $res) \
              --query '{Status: Status, StatusReason: StatusReason, Changes: Changes}')
            # pretty print the changeset
            echo $describe | python -m json.tool
            if ! [[ $describe == *"FAILED"* ]];
            then
              echo
              read -p "Do you want to execute the changeset?[yY|nN]" -n 2 -r
              echo    # move to a new line
              if [[ $REPLY =~ ^[Yy]$ ]]
              then
                  execute_changeset
              else
                  echo "Ok, I'm NOT executing the changeset but I'm NOT deleting it either"
                  echo "You can delete the changeset with the following command:"
                  DRY_RUN=true #THIS prevents the changeset to be actually deleted
                  delete_changeset
              fi
            else
              delete_changeset
              echo "Deleted useless changeset for you"
            fi
        fi
    done
}

execute_changeset()
{
  command="aws cloudformation execute-change-set \
    --change-set-name $res-changeset \
    --profile ${PROFILE} \
    --region $REGION \
    --stack-name $(get_stack_name $res)"
  echo $command
  if ! $DRY_RUN
  then
      $command
  fi
}

delete_changeset()
{
  command="aws cloudformation delete-change-set \
    --change-set-name $res-changeset \
    --profile ${PROFILE} \
    --region $REGION \
    --stack-name $(get_stack_name $res)"
  echo $command
  if ! $DRY_RUN
  then
      $command
  fi
}

validate_stack()
{
    for res in "${RESOURCE[@]}"
    do
        command="aws cloudformation \
        validate-template \
        --profile ${PROFILE} \
        --region $REGION \
        --template-body file://$TEMPLATE_FOLDER/$res.$TEMPLATE_EXTENSION"
        echo $command
        if ! $DRY_RUN
        then
            $command
        fi
    done
}

get_stack_status()
{
    for res in "${RESOURCE[@]}"
    do
        aws cloudformation \
        describe-stacks \
        --profile ${PROFILE} \
        --region $REGION \
        --stack-name $(get_stack_name $res) \
        --query 'Stacks[*].StackStatus'
    done
}

check_if_aligned_with_gitdefaultremote()
{
  git remote update origin
  UPSTREAM='@{u}'
  LOCAL=$(git rev-parse @)
  REMOTE=$(git rev-parse "$UPSTREAM")
  BASE=$(git merge-base @ "$UPSTREAM")

  printf "Checking if the local repo is aligned with the Default Remote.. "

  RES=0
  if [ $LOCAL = $REMOTE ]; then
      echo "Up-to-date"
  elif [ $LOCAL = $BASE ]; then
      echo "Need to pull"
      RES=1
  elif [ $REMOTE = $BASE ]; then
      echo "Need to push"
  else
      echo "Diverged"
      RES=1
  fi
  return $RES

}

git_check()
{
  check_if_aligned_with_gitdefaultremote
  GITALIGNED=$?
  if [[ $GITALIGNED != 0 && $INSANEMODE == false ]]
  then
    echo "WARNING: There are changes on the default remote that are not present locally"
    echo "WARNING: Do a GIT PULL first"
    if [[ $DRYRUN != true ]]
    then
      exit -1
    else
      echo "*Ignoring warning since it is a dry run*"
    fi
  elif [[ $INSANEMODE == true && $DRYRUN == false ]]
  then
    echo "WARNING: USING INSANE MODE. I'm running cloudformation even if git remote is ahead"
  fi
}

has_version()
{
    version=`cat $1 | jq --arg ENVIRONMENT_PARAMETER_NAME "$ENVIRONMENT_PARAMETER_NAME" '(.[] | select(.ParameterKey == $ENVIRONMENT_PARAMETER_NAME) | .ParameterValue)'|sed s/'"'//g`
    echo $version
}

get_stack_name()
{
    resource=$1
    version=$(has_version $PARAMETERS_FOLDER/${SERVICE}-$ENV-$res.json)

    if [ $version ]
    then
        name=${SERVICE}-$ENV-$resource-$version
    else
        name=${SERVICE}-$ENV-$resource
    fi

    echo $name
}

############
### MAIN ###
############

while getopts "vhe:o:s:df" opt
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
        f)
            INSANEMODE=true
            ;;
        v)
            print_version
            exit 1
            ;;
        s)
            SERVICE=$OPTARG
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
    git_check
    create_stack
elif [[ $OPERATION == 'update' ]]
then
    git_check
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
    git_check
    create_changeset_stack
elif [[ $OPERATION == 'validate' ]]
then
    validate_stack
elif [[ $OPERATION == 'status' ]]
then
    get_stack_status
elif [[ $OPERATION == 'delete' ]]
then
    delete_stack
else
    echo "Invalid operation $OPERATION: Allowed values are [create, update, changeset, delete, validate, status]"
    print_help
fi
