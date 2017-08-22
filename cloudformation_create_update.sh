#!/bin/bash

OWNER='owner'
PROFILE='profile-name'
PROJECT='project-name'
ENV='environment'
REGION='eu-west-1'
RESOURCE=()
OPERATION='create'

print_help()
{
    cat << EOF
    usage: $0 [-h] -o [create,update] -e [Environment] stackname1 stackname2 stackname3 ...

    This script create or update cloudformation script

    OPTIONS:
       -h      Show this message
       -e      Environment name
EOF
}

create_stack(){
    for res in "${RESOURCE[@]}"
    do
        command="aws cloudformation \
        create-stack \
        --profile $PROFILE \
        --stack-name $PROJECT-$ENV-$res \
        --template-body file://$res.yaml \
        --parameters file://parameters/$res-parameters-$ENV.json \
        --region $REGION \
        --capabilities CAPABILITY_NAMED_IAM"
        echo $command
        $command

        aws cloudformation \
        wait stack-create-complete \
        --profile $PROFILE \
        --stack-name $PROJECT-$ENV-$res \
        --region $REGION
    done
}

update_stack()
{
    for res in "${RESOURCE[@]}"
    do
        command="aws cloudformation \
        update-stack \
        --profile $PROFILE \
        --stack-name $PROJECT-$ENV-$res \
        --template-body file://$res.yaml \
        --parameters file://parameters/$res-parameters-$ENV.json \
        --region $REGION \
        --capabilities CAPABILITY_NAMED_IAM"
        echo $command
        $command

    done
}


############
### MAIN ###
############

while getopts "he:o:" opt
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
        ?)
            echo "Option/s error/s"
            print_help
            exit -1
            ;;
     esac
done
shift $(( OPTIND - 1 ))

for var in "$@"
do
  RESOURCE+=($var)
done

if [[ $OPERATION == 'create' ]]
then
    create_stack
elif [[ $OPERATION == 'update' ]]
then
    update_stack
else
    echo "Invalid operation $OPERATION: Allowed value are [create, update]"
    print_help
fi