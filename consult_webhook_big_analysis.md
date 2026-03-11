# Workflow Analysis: consult webhook big

## Overview

**Workflow Name:** consult webhook big  
**Workflow ID:** `ayrgzviYf11H3kph`  
**Status:** Active  
**Created:** 2026-02-13 | **Last Updated:** 2026-02-14  
**Version Counter:** 131 (most evolved; 3 predecessor versions exist)  
**Purpose:** Logistics large-file analysis — accepts an Excel (xlsx) file upload, performs AI-driven logistics consulting per batch of rows, then synthesizes all batch results into a final HTML report with charts.

---

## Version History

| Version | ID | Status | Trigger | Analysis Pattern | Models Used |
|---|---|---|---|---|---|
| ver 1 | `BtMKp4zws1mbIz77` | Inactive | Webhook | Single agent loop → Merge → cleanup agent | claude-sonnet-4.5 + grok-code-fast-1 |
| ver 2 | `Hv7mzFlGnisyVENM` | Inactive | Webhook | Switch → 5 parallel agents → Merge | Gemini 2.5 Flash × 5 + claude-sonnet-4.5 |
| ver 3 | `ntGPnU9D0hP1cFda` | Inactive | Execute Workflow Trigger (no webhook) | Same as ver 2 | Gemini 2.5 Flash × 5 + claude-sonnet-4.5 |
| **Final** | `ayrgzviYf11H3kph` | **Active** | Webhook + Chat Trigger | Sequential batch loop → per-batch agent → synthesis agent | Gemini 2.5 Flash + claude-sonnet-4.5 |

### Evolution Summary

- **Ver 1 → Ver 2:** Replaced the single looping agent with 5 parallel agents selected by `loopIndex` via a Switch node, enabling parallel processing of multiple data chunks simultaneously.
- **Ver 2 → Ver 3:** Replaced the Webhook trigger with an `Execute Workflow Trigger`, making it callable as a sub-workflow.
- **Ver 3 → Final:** Reverted to a sequential per-batch loop pattern (simpler), added a second entry point (Chat trigger with file upload UI), introduced an MCP Client tool for geospatial routing (`valhalla_route`), and added a Structured Output Parser to enforce output schema.

---

## Architecture: consult webhook big (Final)

### Triggers (2)

1. **Webhook** (`f3fb6cc7`) — POST to path `10df9f3d-ca2d-4a30-9d49-472866901991`; accepts binary file upload (`data`); response via node.
2. **When chat message received** (`d1eb45f0`) — Public chat UI; allows file uploads; Korean UI labels:
   - Title: `물류 대형 파일 분석 👋` (Logistics Large File Analysis)
   - Subtitle: `분석할 엑셀 파일을 선택하고 분석을 지시하세요.` (Select an Excel file to analyze and instruct the analysis)
   - Placeholder: `무엇을 분석할까요?` (What shall I analyze?)

### Data Flow

```
Webhook ──────────────► Extract from File  (xlsx, binary: data)  ──┐
                                                                    │
Chat Trigger ─────────► Extract from File1 (xlsx, binary: data0) ──┤
                                                                    ▼
                                                        Loop Over Items (batch 5000)
                                                           │              │
                                                    [done, out[0]]  [each batch, out[1]]
                                                           │              │
                                                        Aggregate     Aggregate1
                                                           │              │
                                                           │           AI Agent2 ──► (back to Loop)
                                                           │
                                                        AI Agent1 (synthesis)
                                                           │
                                            ┌──────────────┴──────────────┐
                                            ▼                             ▼
                                   Respond to Webhook            Convert to File
                                                               (consult.html, unused output)
```

---

## Node Details

### Ingestion Nodes

| Node | Type | Role |
|---|---|---|
| Webhook | `n8n-nodes-base.webhook` | Receives POST with xlsx file attachment |
| When chat message received | `@n8n/n8n-nodes-langchain.chatTrigger` | Public chat UI with file upload |
| Extract from File | `n8n-nodes-base.extractFromFile` | Parses xlsx from `data` binary (Webhook path) |
| Extract from File1 | `n8n-nodes-base.extractFromFile` | Parses xlsx from `data0` binary (Chat path) |

### Processing Nodes

| Node | Type | Config |
|---|---|---|
| Loop Over Items | `n8n-nodes-base.splitInBatches` | Batch size: 5000 rows |
| Aggregate | `n8n-nodes-base.aggregate` | Aggregates all items (triggered on loop completion) |
| Aggregate1 | `n8n-nodes-base.aggregate` | Aggregates each batch (triggered each iteration) |

### AI Nodes

#### AI Agent2 — Per-Batch Logistics Consultant
- **Node:** `ce035561` (AI Agent2)
- **Model:** `google/gemini-2.5-flash` via OpenRouter
- **Input:** `{{ $json }}` (each batch of rows)
- **System Prompt (Korean):**
  > 물류전문가로서 데이터를 해석하고 개선 사항을 컨설팅 한다.  
  > 1. 물류 비용 개선  
  > 2. 물류 권역 클러스터링  
  > 3. 인건비 절감 방안  
  > 4. 프로세스 개선
- **Translation:** As a logistics expert, interpret the data and consult on: (1) logistics cost improvement, (2) logistics zone clustering, (3) labor cost reduction, (4) process improvement.
- **Loop behavior:** Output feeds back to `Loop Over Items` input, continuing the iteration.

#### AI Agent1 — Synthesis & Report Generator
- **Node:** `2f990288` (AI Agent1)
- **Model:** `anthropic/claude-sonnet-4.5` via OpenRouter
- **Input:** `{{ $json.data }}` (all aggregated batch outputs)
- **Tools:**
  - **MCP Client routing** (`9ffde9bb`) — Calls `valhalla_route` tool at `http://host.docker.internal.:3001/mcp` (timeout: 60s); used for geospatial route optimization queries
- **Output Parser:** Structured Output Parser enforces JSON schema: `{ "output": "string", "insights": ["string", ...] }`
- **System Prompt (Korean):**
  > 입력된 여러개의 output은 하나의 데이터를 나누어서 분석한 내용이므로 모든 데이터는 합산하고 분석내용은 그에 따라 정리되어야한다.  
  > html포맷으로 만들며 주요 heading 문도 html 포맷으로 변환하고 markdown 형식을 쓰지 않는다, 이해를 돕기 위해 차트용 테이블을 생성한다. chart 필요시 html과 javascript를 추가한다.  
  > 차트를 위해서는 고정된 ID를 가진 `<canvas>` 요소만 출력합니다. HTML 안에서 `new Chart(...)` 를 호출하지 마세요. Chart.js 초기화는 프론트엔드에서 처리합니다.
- **Translation:** All batch outputs represent divided analysis of one dataset; aggregate all data and organize analysis accordingly. Output as HTML (no markdown), include chart-supporting tables, add `<canvas>` elements with fixed IDs for charts but do NOT call `new Chart(...)` — Chart.js initialization is handled by the frontend.

### Output Nodes

| Node | Type | Behavior |
|---|---|---|
| Respond to Webhook | `n8n-nodes-base.respondToWebhook` | Returns all items (the structured output with `output` + `insights`) to the HTTP caller |
| Convert to File | `n8n-nodes-base.convertToFile` | Converts `output` field to `consult.html` — **Note: output is disconnected (no downstream node)** |

---

## Key Design Patterns

### 1. Iterative Batch Loop with Feedback
The `Loop Over Items` node processes rows in 5000-row batches. Each batch flows through `Aggregate1 → AI Agent2`, and the AI Agent2 output loops **back** into `Loop Over Items`. This means each batch's analysis result is reinjected as context for subsequent iterations, creating an accumulating context window.

### 2. Dual Entry Point
Both a raw Webhook (for programmatic API use) and a Chat UI trigger share the same processing pipeline starting from `Loop Over Items`. This allows both a user-facing chat interface and an API integration.

### 3. MCP Integration for Route Optimization
AI Agent1 (the synthesis agent) has access to the `valhalla_route` MCP tool, enabling it to call an internal routing engine for real geospatial route calculations as part of logistics optimization recommendations.

### 4. Frontend-Delegated Chart Rendering
AI Agent1 is instructed to output only `<canvas>` elements with fixed IDs — Chart.js initialization is intentionally omitted from the AI output and handled externally by the consuming frontend. This architecture separates AI-generated markup from frontend chart lifecycle management.

### 5. Structured Output Enforcement
The Structured Output Parser constrains AI Agent1's response to `{ output: string, insights: string[] }`, making downstream consumption predictable.

---

## Observations & Potential Issues

1. **Convert to File disconnected:** The `Convert to File` node outputs to an empty array (`[]`) — the `consult.html` file is generated but not uploaded, stored, or sent anywhere. This is likely a dead branch.

2. **Loop feedback ambiguity:** AI Agent2's output feeds back to `Loop Over Items` port 0 (the main input), which could cause unexpected re-batching if the agent output contains multiple items. The intent appears to be accumulating per-batch analyses, but the data shape flowing back into the loop may need validation.

3. **Webhook path collision:** All three webhook-triggered versions (ver 1, ver 2, and the final) share the same webhook path `10df9f3d-ca2d-4a30-9d49-472866901991`. Since only the final version is active, this is not currently a conflict, but reactivating any prior version would cause a collision.

4. **No error handling:** No error nodes or fallback branches are defined. API failures (OpenRouter, MCP) or malformed xlsx files will cause silent workflow failures.

5. **Batch size fixed at 5000:** The 5000-row batch size is hardcoded. For very small files this may result in a single batch (no looping benefit), and for files with columns heavy with text this may exceed the model's token context.

---

## Credentials Used

| Credential | ID | Used By |
|---|---|---|
| OpenRouter account | `bmootghisT1sWFIT` | AI Agent1 (claude-sonnet-4.5), AI Agent2 (gemini-2.5-flash) |

---

## Summary

`consult webhook big` is the production-active version of a logistics data consulting pipeline. It accepts large Excel file uploads via either an HTTP webhook or a chat UI, chunks the data into 5000-row batches, runs each batch through a Gemini-powered logistics expert agent, then synthesizes all batch analyses into a single HTML report (with embedded charts) using Claude. The synthesis agent also has access to a Valhalla routing MCP server for real geospatial calculations. The final structured output (`output` + `insights[]`) is returned to the caller.
