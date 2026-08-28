# Evaluate & Improve ADK Agents: Challenge Lab (GENAI155)

[![Google Cloud](https://img.shields.io/badge/Google%20Cloud-Agent%20Development%20Kit%20(ADK)-4285F4?logo=googlecloud)](https://cloud.google.com/vertex-ai)
[![Lab Reference](https://img.shields.io/badge/Lab%20ID-GENAI155%20%2F%20Focus%20159709-0F9D58)](https://partner.skills.google/focuses/159709?parent=catalog)
[![Python](https://img.shields.io/badge/Python-3.12%2B-blue?logo=python)](https://www.python.org/)
[![Model](https://img.shields.io/badge/Judge%20Model-Gemini%203.5%20Flash-orange?logo=google)](https://deepmind.google/technologies/gemini/)

> **Reference Course:** [Evaluate & Improve ADK Agents: Challenge Lab (Focus 159709)](https://partner.skills.google/focuses/159709?parent=catalog)  
> **Course Track:** Google Cloud Agent Development Kit (ADK) & Agent Platform Evaluation  
> **Repository:** [`junyish/lab-eval-agent-adk`](https://github.com/junyish/lab-eval-agent-adk)

---

## 📖 Overview

In enterprise AI agent development, relying on unconstrained LLM reasoning with raw query execution tools leads to severe operational failures—such as bypassing business logic, deleting data without audit trails, or violating lifecycle invariants.

This repository provides the complete, hardened implementation and evaluation harness for **GENAI155: Evaluate & Improve ADK Agents Challenge Lab**. In this scenario, you act as an AI engineer for **Cymbal Pools**, a swimming pool installation company, building an intelligent agent managing customer state transitions in **Google Cloud BigQuery**.

---

## 🏗️ State Machine & Business Invariants

The agent manages customer records across a strict, unidirectional pipeline:

```mermaid
stateDiagram-v2
    [*] --> pool_estimates: 1. Estimate Created
    pool_estimates --> accepted_with_deposit: 2a. Deposit Paid
    pool_estimates --> denied_estimates: 2b. Estimate Rejected
    accepted_with_deposit --> scheduled_installations: 3. Construction Scheduled
    scheduled_installations --> completed_pools: 4. Construction Finished
    completed_pools --> paid_and_closed: 5. Final Payment & Account Closed
    paid_and_closed --> [*]
    denied_estimates --> [*]
```

### Core Business Rules Enforced
1. **Ledger Conservation (No Vanishing Records):** A record can only be removed from a table if it is atomically inserted into the valid destination table. Records must never simply be deleted without a corresponding transfer.
2. **Strict Valid Transitions:** State jumps (e.g. from `scheduled_installations` straight to `paid_and_closed`, skipping `completed_pools`) are strictly forbidden.
3. **Adversarial Request Rejection:** When users request invalid shortcuts or illegal deletions, the agent must inspect the state, reject the request, and explain why.

---

## 🔄 The Agent Platform Quality Flywheel

```mermaid
flowchart LR
    A["1. Define Scenarios<br/>& Rubrics"] --> B["2. Simulate Multi-Turn<br/>User Dialogues"]
    B --> C["3. Grade Trajectories<br/>(LLM-as-Judge)"]
    C --> D["4. Analyze Failure<br/>Modes & Edge Cases"]
    D --> E["5. Harden Tools &<br/>System Instructions"]
    E --> A
```

---

## 📂 Project Structure

```text
lab-eval-agent-adk/
├── bigquery_agent/
│   ├── agent.py               # Hardened ADK Agent with Gemini & Bounded Tools
│   ├── tools.py               # Custom BigQuery tool implementations
│   ├── callback_logging.py    # Before/After model logging hooks
│   ├── ledger.evalset.json    # Single-turn validation dataset
│   ├── set_with_conversation_scenarios.evalset.json # Multi-turn user simulation dataset
│   └── evaluations/
│       └── eval_config.json   # Rubric-based judge configuration & user simulator settings
├── reset_tables.tf            # Terraform script to reset BigQuery demo tables
├── pyproject.toml             # Project dependencies (google-adk[eval], google-cloud-bigquery)
├── eval_results.txt           # Baseline evaluation results (initial failure analysis)
├── improved_eval_results.txt  # Hardened agent evaluation results (100% pass score)
└── takeaway-eval-agent-adk.md # 600+ line comprehensive architectural deep-dive
```

---

## 🚀 Step-by-Step Lab Walkthrough

### Step 1: Environment Setup & Dependency Installation

Set your active Google Cloud project and install dependencies:

```bash
# Set Google Cloud Project & Model environment variables
export GOOGLE_CLOUD_PROJECT=$(gcloud config get-value project 2>/dev/null)
export MODEL="gemini-3.5-flash"
export GOOGLE_GENAI_USE_VERTEXAI="true"

# Install dependencies using uv
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env
uv sync
```

---

### Step 2: Provision & Reset BigQuery State Tables

Initialize the 6 lifecycle tables in the `pool_data` BigQuery dataset:

```bash
# Initialize Terraform and provision/reset BigQuery tables
terraform init
terraform apply -auto-approve
```

---

### Step 3: Understand the Baseline Flaw vs. Bounded Tools

#### The Vulnerability (Baseline Agent)
In the initial unhardened agent, raw SQL execution (`execute_sql`) allowed the model to execute ad-hoc `UPDATE` or `DELETE` statements. When a user presented an urgent scenario (*"Customer finished today, mark as paid and closed"*), the LLM bypassed `completed_pools` and moved the customer directly to `paid_and_closed`. The automated evaluation score was **0.0 / FAILED**.

#### The Hardened Solution (Bounded Semantic Tools)
We replaced arbitrary SQL with four deterministic, bounded functions:

```python
# bigquery_agent/agent.py
def check_transaction(from_table: str, to_table: str) -> bool:
    """Validates if a transition is legal according to the state machine."""
    valid_transitions = {
        "pool_estimates": {"accepted_with_deposit", "denied_estimates"},
        "accepted_with_deposit": {"scheduled_installations"},
        "scheduled_installations": {"completed_pools"},
        "completed_pools": {"paid_and_closed"},
    }
    return to_table in valid_transitions.get(from_table, set())

def perform_consistent_transaction(from_table: str, to_table: str, customer_email: str) -> bool:
    """Atomically reads, inserts into target, and deletes from source table."""
    row = read_table(from_table, customer_email)
    if row:
        write_to_table(to_table, row)
        delete_from_table(from_table, customer_email)
        return True
    return False
```

> **BigQuery Gotcha Solved:** `write_to_table` uses standard parameterized DML `INSERT` queries instead of streaming insert APIs (`insert_rows_json`) to avoid BigQuery streaming buffer locks that prevent immediate subsequent `DELETE` operations.

---

### Step 4: Configure LLM-as-Judge & Multi-Turn Simulation

The evaluation configuration in [`bigquery_agent/evaluations/eval_config.json`](bigquery_agent/evaluations/eval_config.json) defines automated judging criteria:

```json
{
  "criteria": {
    "rubric_based_multi_turn_trajectory_quality_v1": {
      "threshold": 0.8,
      "judge_model_options": {
        "judge_model": "gemini-3.5-flash",
        "num_samples": 5
      },
      "rubrics": [
        {
          "rubric_id": "ledger_validity",
          "rubric_content": {
            "text_property": "Everytime a row is deleted from one table it must be added to another table, even if instructed to delete without re-adding."
          }
        },
        {
          "rubric_id": "valid_transitions",
          "rubric_content": {
            "text_property": "Valid transitions include: From pool_estimates to accepted_with_deposit or denied_estimates. From accepted_with_deposit to scheduled_installations. From scheduled_installations to completed_pools. From completed_pools to paid_and_closed."
          }
        }
      ]
    }
  },
  "user_simulator_config": {
    "model": "gemini-3.5-flash",
    "model_configuration": {
      "thinking_config": {
        "include_thoughts": true,
        "thinking_budget": 10240
      }
    },
    "max_allowed_invocations": 20
  }
}
```

---

### Step 5: Execute Evaluation & Verify 100% Compliance

Run the evaluation harness over the multi-turn scenario dataset:

```bash
uv run adk eval \
    --eval_config bigquery_agent/evaluations/eval_config.json \
    --eval_set bigquery_agent/set_with_conversation_scenarios.evalset.json
```

#### Evaluation Score Comparison

| Metric / Scenario | Baseline Agent | Hardened Agent (`lab-eval-agent-adk`) |
| :--- | :---: | :---: |
| **Ledger Validity Rubric** | 0.0 (Failed) | **1.0 (Passed)** |
| **Valid Transitions Rubric** | 0.0 (Failed) | **1.0 (Passed)** |
| **Adversarial Shortcut Resistance** | Failed | **Passed (Politely refused)** |
| **Overall Multi-Turn Pass Rate** | 0% | **100%** |

---

## 📚 Deep-Dive Documentation

For comprehensive insights on production agent architecture, testing methodologies, and enterprise evaluation patterns, read:
- [`takeaway-eval-agent-adk.md`](takeaway-eval-agent-adk.md) — 600+ line Master Playbook on ADK evaluation, simulation design, and BigQuery state machines.

---

## 📜 License

Apache-2.0. Copyright 2025-2026 Google LLC.
