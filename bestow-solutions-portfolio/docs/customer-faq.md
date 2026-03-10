Customer Integration FAQ


# Customer Integration FAQ

## Purpose

This document provides answers to common questions from customers and partners integrating with the platform APIs.

It is designed to help integration teams quickly troubleshoot common issues and understand API behavior.

---

# What authentication method does the API use?

The API uses token-based authentication.

Each request must include the following header:
Authorization: Bearer <access_token>


Tokens are generated through the authentication endpoint and expire after a defined period.

---

# What data format should requests use?

All API requests must use JSON format.

Required header:
Content-Type: application/json


Example request payload:

```json
{
  "customer_id": "12345",
  "coverage_amount": 250000
}
How can I test the API before integrating?
We recommend using API testing tools such as:

Postman

curl

Insomnia

These tools allow you to verify authentication, payload formatting, and response behavior before building the integration.

What should I do if I receive a 401 error?
A 401 Unauthorized response usually indicates an authentication issue.

Verify the following:

token is included in the request header

token has not expired

token has the required permissions

If the token has expired, generate a new token using the authentication endpoint.

What should I do if I receive a 400 error?
A 400 Bad Request response typically indicates a payload validation issue.

Check the following:

required fields are included

data types are correct

JSON formatting is valid

enum values are valid

Compare your payload with the API documentation example.

How do I troubleshoot integration failures?
Follow this troubleshooting workflow:

Confirm endpoint and HTTP method

Verify authentication

Validate headers

Inspect payload structure

Review response codes

Check logs if available

If the issue persists, contact support with request details.

What information should I include when contacting support?
Provide the following information to help diagnose issues quickly:

endpoint used

request method

timestamp

request payload (sanitized if needed)

response code

response body

correlation ID if available

Author
Colleen Cummings
Senior Technical Consultant & Cloud Integration Architect





