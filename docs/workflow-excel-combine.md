# Workflow: Multiple Excel Files to Combined JSON

## Overview

**Workflow ID:** `wWylGWwh9ytKdobV`  
**Status:** Active  
**Endpoint:** `POST /webhook/excel-combine`

Accepts multiple `.xlsx` files via a single HTTP POST request and returns all rows from all files merged into one JSON array.

---

## Flow Diagram

```
Webhook (POST)
    → Split Binary Files (Code)
        → Extract XLSX Data (ExtractFromFile)
            → Aggregate All Rows (Aggregate)
                → Format Output (Code)
                    → Respond to Webhook
```

---

## Nodes

### 1. Webhook
- **Type:** `n8n-nodes-base.webhook` (typeVersion 2.1)
- **Method:** POST
- **Path:** `excel-combine`
- **Response Mode:** `responseNode` (waits for Respond to Webhook node)
- **Binary Property:** `data`
- **webhookId:** `7984c8c6-b17b-4e50-9f43-f447415b95f3`

> ⚠️ `webhookId` is required for production URL registration. Without it, the workflow activates but the route is never registered — resulting in a 404.

---

### 2. Split Binary Files
- **Type:** `n8n-nodes-base.code` (typeVersion 2)
- **Purpose:** Splits each uploaded binary file from the single webhook item into individual items (one per file), so downstream nodes process each file separately.

```js
const item = $input.first();
const binary = item.binary || {};
const result = [];

for (const key of Object.keys(binary)) {
  const fileData = binary[key];
  result.push({
    json: {
      fileName: fileData.fileName || key,
      fileKey: key
    },
    binary: {
      data: fileData
    }
  });
}

if (result.length === 0) {
  throw new Error('No Excel files found. Upload .xlsx files via multipart/form-data POST.');
}

return result;
```

---

### 3. Extract XLSX Data
- **Type:** `n8n-nodes-base.extractFromFile` (typeVersion 1.1)
- **Operation:** `xlsx`
- **Purpose:** Parses each binary item as an Excel file and outputs its rows as individual items.

---

### 4. Aggregate All Rows
- **Type:** `n8n-nodes-base.aggregate` (typeVersion 1)
- **Mode:** `aggregateAllItemData`
- **Purpose:** Collects all row items (from all files) into a single item with a `data` array.

---

### 5. Format Output
- **Type:** `n8n-nodes-base.code` (typeVersion 2)
- **Purpose:** Wraps the aggregated data in a clean response envelope.

```js
const rows = $input.first().json.data || [];

return [{
  json: {
    success: true,
    totalRows: rows.length,
    combinedData: rows
  }
}];
```

---

### 6. Respond to Webhook
- **Type:** `n8n-nodes-base.respondToWebhook` (typeVersion 1.1)
- **Responds with:** `json`
- **Body:** `={{ $json }}`

---

## Usage

```bash
curl -X POST http://<host>:5678/webhook/excel-combine \
  -F "file1=@data1.xlsx" \
  -F "file2=@data2.xlsx" \
  -F "file3=@data3.xlsx"
```

### Response

```json
{
  "success": true,
  "totalRows": 150,
  "combinedData": [
    { "column1": "value", "column2": "value", ... },
    ...
  ]
}
```

---

## Issues & Fixes

### Production URL 404

**Symptom:** Test URL (`/webhook-test/excel-combine`) worked, but production URL (`/webhook/excel-combine`) returned 404 even after activating the workflow.

**Root Cause:** The webhook node was created via API without a `webhookId` field and used `typeVersion: 2` instead of `2.1`. In n8n, `webhookId` is required for the production webhook route to be registered in the database at activation time. Without it, n8n silently skips registration.

**Fix:**
1. Added `webhookId` (UUID) to the webhook node
2. Updated `typeVersion` from `2` → `2.1`
3. Changed binary option from `binaryData: true` → `binaryPropertyName: "data"`
4. Deactivated and reactivated the workflow via API to re-register the route

---

## Creation Date

2026-04-14
