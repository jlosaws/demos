import * as fs from 'node:fs/promises'; 

export const lambda_handler = async (event) => {

  var base64body;

  try {
    const img = await fs.readFile('./images/aws.png');
    base64body = Buffer.from(img).toString('base64');
  } catch (err) {
    console.error(err);
  }
  
  const response = {
    'headers': { 
        "Content-Type": "image/png", 
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token"
      },
    'statusCode': 200,
    'body': base64body,
    'isBase64Encoded': true
  }

  console.log(response);

  return response
}