import { app, HttpRequest, HttpResponseInit, InvocationContext } from "@azure/functions";
import {
    TextAnalysisClient,
    AzureKeyCredential,
    KnownPiiEntityDomain,
    KnownPiiEntityCategory,
    KnownHealthcareEntityCategory,
  } from "@azure/ai-language-text";

import * as dotenv from "dotenv";

dotenv.config();

app.http('PiiFiltering', {
    methods: ['POST'],
    authLevel: 'anonymous',
    handler: PiiFiltering
});

export async function PiiFiltering(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {

    console.log(`Running recognizePii sample`);
    
    context.log(`Http function processed request for url "${request.url}"`);

    const documents = [request.query.get('documents') || await request.text() || 'world'];


    const endpoint = process.env.ENDPOINT ?? "";
    const apiKey = process.env.LANGUAGE_API_KEY ?? "";
    
    
    
    const client = new TextAnalysisClient(endpoint, new AzureKeyCredential(apiKey));
  
  
    const [result] = await client.analyze("PiiEntityRecognition", documents, "en", {      
      domainFilter: KnownPiiEntityDomain.Phi,
      categoriesFilter: [
        // KnownPiiEntityCategory.All,
        KnownPiiEntityCategory.HRIdentityCardNumber,        
        KnownPiiEntityCategory.PhoneNumber,
        KnownPiiEntityCategory.USSocialSecurityNumber,
        KnownPiiEntityCategory.Person,
        KnownPiiEntityCategory.Age

    });

    
    if (!result.error) {
      console.log(`Redacted text: "${result["redactedText"]}"`);
      console.log("Pii Entities: ");
      for (const entity of result["entities"]) {
        console.log(`\t- "${entity.text}" of type ${entity.category}`);
      }
    }

    const response: HttpResponseInit = {
      body: JSON.stringify(result), // Set the response body to the result object
      status: 200, // Set the response status code
      headers: { "Content-Type": "application/json" }, // Set the response headers
      cookies: [] // Set the response cookies if needed
  };

    return response ;
  }