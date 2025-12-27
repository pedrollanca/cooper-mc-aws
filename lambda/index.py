import json
import boto3
import os

ec2 = boto3.client('ec2')
sns = boto3.client('sns')
instance_id = os.environ['INSTANCE_ID']
sns_topic_arn = os.environ.get('SNS_TOPIC_ARN', '')

def send_notification(subject, message):
    if sns_topic_arn:
        try:
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject=subject,
                Message=message
            )
        except Exception as e:
            print(f"Failed to send notification: {str(e)}")

def handler(event, context):
    path = event.get('rawPath', event.get('path', ''))
    action = path.strip('/').lower()

    try:
        if action == 'start':
            ec2.start_instances(InstanceIds=[instance_id])
            send_notification(
                'Minecraft Server Starting',
                f'The Minecraft server is starting.\n\nInstance ID: {instance_id}\n\nThe server will be ready in a few minutes.'
            )
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'message': 'Starting instance', 'instance_id': instance_id})
            }
        elif action == 'stop':
            ec2.stop_instances(InstanceIds=[instance_id])
            send_notification(
                'Minecraft Server Stopping',
                f'The Minecraft server is stopping.\n\nInstance ID: {instance_id}\n\nThe server will be offline shortly.'
            )
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'message': 'Stopping instance', 'instance_id': instance_id})
            }
        elif action == 'restart':
            ec2.reboot_instances(InstanceIds=[instance_id])
            send_notification(
                'Minecraft Server Restarting',
                f'The Minecraft server is restarting.\n\nInstance ID: {instance_id}\n\nThe server will be back online in a few minutes.'
            )
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'message': 'Restarting instance', 'instance_id': instance_id})
            }
        elif action == 'status':
            response = ec2.describe_instances(InstanceIds=[instance_id])
            state = response['Reservations'][0]['Instances'][0]['State']['Name']
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'instance_id': instance_id, 'state': state})
            }
        else:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Invalid action. Use /start, /stop, /restart, or /status'})
            }
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }
