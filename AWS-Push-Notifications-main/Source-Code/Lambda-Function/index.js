const AWS = require('aws-sdk')

exports.handler = async (event) => {

    //make SNS device endpoint the ARN for the message to be sent to
    //if want to send to all -- remove the device token -- make it general to the SNS platform application
    const TargetArn = 'arn:aws:sns:us-east-1:713026491585:endpoint/GCM/PushNotifications/2d65b2b2-af11-3411-9c17-685d40ce80b7';
    
    let payload = {
        default : 'default',
        GCM:{
            notification:{
                body: 'It Is Working!',
                title: 'New Notification!',
                sound: 'default'
            }
        }
    }
    
    payload.GCM = JSON.stringify(payload.GCM);
    payload = JSON.stringify(payload);
    
    const params_sns = {
        Message: payload,
        TargetArn: TargetArn,
        MessageStructure : 'json'
    }
    
    //choose AWS configuration
    const new_sns = new AWS.SNS({apiVersion: '2010-03-31'})
    
    //queue like behavior
    await new_sns.publish(params_sns).promise();    
    
    const response = {
        statusCode: 200,
        body: JSON.stringify('Hello from Lambda!'),
    };
    return response;
};
