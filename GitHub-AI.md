# GitHub AI Standup Agent - Technical Documentation

## Overview

The **GitHub AI Standup Agent** is an AWS Lambda function that collects, analyzes, and generates AI-powered daily standup reports for development teams using GitHub. It integrates with the GitHub API to fetch developer activity, PR metrics, and code delivery statistics, then uses OpenAI to generate comprehensive standup summaries.

## Purpose

This agent automates the daily standup process by:
1. **Collecting GitHub metrics** for each team member (commits, PRs, reviews, issues)
2. **Analyzing PR delivery flow** (time to review, time to merge, blockers)
3. **Storing detailed PR facts** for manager analytics
4. **Generating AI-powered summaries** of developer activity
5. **Providing delivery insights** with risk flags and blockers

---

## Architecture Flow

```
┌─────────────────┐
│  EventBridge    │  (Scheduled or manual trigger)
│  or Manual      │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────┐
│           GitHub AI Standup Agent (Lambda)              │
│                                                         │
│  1. Fetch project configuration & members              │
│  2. Get GitHub integration & access token              │
│  3. For each repository:                               │
│     - Fetch updated PRs (last 14 days)                 │
│     - Store PR facts in delivery-facts table           │
│  4. For each team member:                              │
│     - Fetch GitHub events (commits, PRs, reviews)      │
│     - Calculate metrics & analyze activity             │
│     - Generate AI summary with GPT-4                   │
│     - Store in github-metrics table                    │
└─────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────┐
│              DynamoDB Tables                            │
│                                                         │
│  • zaph-github-metrics  (User daily metrics)           │
│  • zaph-delivery-facts  (PR delivery analytics)        │
│  • zaph-core            (Projects, members)            │
│  • zaph-integrations    (GitHub org integration)       │
└─────────────────────────────────────────────────────────┘
```

---

## Data Sources

### 1. Configuration Tables (DynamoDB)

#### **zaph-integrations** Table
Stores GitHub organization integration details:
```javascript
{
  "PK": "TENANT#tnt_xxx",
  "SK": "PROVIDER#GITHUB#ORG",
  "orgName": "my-github-org",
  "accountId": "12345678",
  "githubInstallationId": "98765432",
  "accessToken": "encrypted-or-from-secrets"
}
```

#### **zaph-core** Table - Project Configuration
```javascript
{
  "PK": "PROJECT#proj_xxx",
  "SK": "TENANT#tnt_xxx",
  "projectId": "proj_xxx",
  "projectName": "Backend Services",
  "scopes": {
    "PROVIDER#GITHUB#ORG": {
      "repos": [
        "api-gateway",
        "auth-service"
      ],
      "branches": [
        "my-org/api-gateway:*",        // All branches
        "my-org/auth-service:main",    // Only main branch
        "my-org/auth-service:develop"  // Only develop branch
      ]
    }
  }
}
```

#### **zaph-core** Table - Project Members
```javascript
{
  "PK": "TENANT#tnt_xxx",
  "SK": "PROJECT_MEMBER#proj_xxx#user@example.com",
  "userEmail": "user@example.com",
  "userId": "user_xxx",
  "fullName": "John Doe",
  "role": "DEVELOPER"
}
```

#### **zaph-core** Table - GitHub Username Mapping
```javascript
{
  "PK": "TENANT#tnt_xxx",
  "SK": "USER#user@example.com#GITHUB#USERNAME",
  "githubUsername": "johndoe",
  "githubUserId": "123456"
}
```

---

## Branch & Repository Scoping

### How Scoping Works

The agent supports fine-grained control over which repositories and branches to monitor:

#### **Repository Scoping**
- Defined in `scopes.repos` array
- Only specified repositories are queried
- Example: `["api-gateway", "auth-service"]`

#### **Branch Scoping**
Branches are defined in `scopes.branches` with format: `owner/repo:branch`

**Wildcard Support:**
```javascript
"branches": [
  "my-org/api-gateway:*",        // ✅ Monitor ALL branches
  "my-org/auth-service:main",    // ✅ Only main branch
  "my-org/auth-service:develop"  // ✅ Only develop branch
]
```

**Filtering Logic:**
1. **Parse branches** into a `branchMap`:
   ```javascript
   {
     "my-org/api-gateway": ["*"],
     "my-org/auth-service": ["main", "develop"]
   }
   ```

2. **Filter PRs** by base branch:
   - If branch map contains `"*"` → Accept all PRs
   - Otherwise → Only accept PRs where `baseBranch` matches allowed list

3. **Optimize GitHub searches** when possible:
   - For specific branches: Add `base:main base:develop` to search query
   - For wildcards: Fetch all PRs, filter after retrieval

---

## GitHub Metrics Captured

### Per User, Per Day Metrics

The agent captures comprehensive activity for each developer:

#### **1. Code Commits**
- **Source:** `PushEvent` from GitHub Events API
- **What's captured:**
  - Total number of commits
  - Repositories where commits occurred
  - Commit timestamps (within timezone window)

#### **2. Pull Requests**

**PR Opened:**
- **Source:** `PullRequestEvent` with `action: "opened"`
- **Data captured:**
  - PR number, title, description
  - Repository name
  - Base branch & head branch
  - Author information
  - Labels, draft status
  - File changes (additions, deletions, files changed)
  - Creation timestamp

**PR Merged:**
- **Source:** `PullRequestEvent` with `action: "closed"` and `merged_at` present
- **Data captured:**
  - Merge timestamp
  - Time from creation to merge
  - Approvals before merge
  - Changes requested count

**PR Reviewed:**
- **Source:** `PullRequestReviewEvent`
- **Data captured:**
  - Reviewer username
  - Review state (APPROVED, CHANGES_REQUESTED, COMMENTED)
  - Review submission timestamp
  - Comments in review

#### **3. Issues**
- **Opened:** `IssuesEvent` with `action: "opened"`
- **Closed:** `IssuesEvent` with `action: "closed"`

#### **4. Code Changes**
- **Lines added:** Sum of additions across all PR files
- **Lines deleted:** Sum of deletions across all PR files
- **Changed files:** Total files modified in PRs

#### **5. PR Collaboration Data**

**Requested Reviewers:**
```javascript
{
  "githubUsername": "reviewer-name",
  "githubUserId": "123456",
  "requestedAt": "2026-02-15T10:30:00Z",
  "hasReviewed": false
}
```

**Comment Activity:**
- Total comments on PRs
- Comment participants
- Mentioned users (`@username` in comments)
- Last comment timestamp

---

## PR Facts & Delivery Flow

### What Are PR Facts?

PR Facts are detailed analytics records stored in the `zaph-delivery-facts` table that track the entire lifecycle of a pull request for delivery metrics and manager analytics.

### PR Fact Data Structure

```javascript
{
  "PK": "TENANT#tnt_xxx#PROJECT#proj_xxx#REPO#owner/repo",
  "SK": "PR#123",
  
  // Metadata
  "tenantId": "tnt_xxx",
  "projectId": "proj_xxx",
  "projectName": "Backend Services",
  "integrationId": "PROVIDER#GITHUB#ORG",
  "providerAccountId": "12345678",
  "providerOrgName": "my-org",
  "repoFullName": "my-org/api-gateway",
  
  // PR Details
  "prNumber": 123,
  "prId": "98765432",
  "prNodeId": "PR_kwDOAbc123",
  "prTitle": "feat: Add user authentication",
  "prDescription": "Implements JWT-based authentication...",
  "prUrl": "https://github.com/my-org/api-gateway/pull/123",
  "prType": "feature", // feature, bugfix, refactor, etc.
  
  // Status
  "state": "open", // open, closed
  "isDraft": false,
  "isMerged": false,
  "isClosed": false,
  
  // Timestamps
  "createdAt": "2026-02-10T14:30:00Z",
  "updatedAt": "2026-02-15T09:15:00Z",
  "mergedAt": null,
  "closedAt": null,
  
  // Branches
  "baseBranch": "main",
  "headBranch": "feature/auth",
  
  // Author
  "authorGithubUsername": "johndoe",
  "authorGithubUserId": "123456",
  "authorZaphEmail": "john@example.com",
  "authorFullName": "John Doe",
  
  // Code Changes
  "additions": 450,
  "deletions": 120,
  "changedFiles": 12,
  "fileExtensions": ["js", "ts", "json"],
  "fileTypes": ["source_code", "config"],
  
  // Labels & Metadata
  "labels": ["feature", "backend"],
  
  // Reviews
  "requestedReviewers": [
    {
      "githubUsername": "reviewer1",
      "githubUserId": "789",
      "zaphUserEmail": "reviewer@example.com",
      "fullName": "Jane Smith"
    }
  ],
  "actualReviewers": [
    {
      "githubUsername": "reviewer1",
      "githubUserId": "789",
      "reviewState": "APPROVED",
      "reviewedAt": "2026-02-14T16:00:00Z"
    }
  ],
  "approvalCount": 1,
  "changesRequestedCount": 0,
  
  // Collaboration
  "commentCount": 8,
  "reviewCount": 2,
  "commentParticipants": ["johndoe", "reviewer1", "manager"],
  "mentionedUsers": ["@tech-lead", "@devops"],
  
  // Blockers
  "blockers": [
    {
      "type": "pending_reviews",
      "details": "Awaiting approval from 1 reviewer(s)"
    }
  ],
  
  // Merge Status
  "mergeable": true,
  "mergeableState": "clean", // clean, unstable, blocked, dirty
  
  // 🔥 DELIVERY FLOW METRICS 🔥
  "deliveryFlow": {
    // Time Metrics (in hours)
    "timeToFirstReview": 4.5,
    "timeToFirstApproval": 28.2,
    "timeToMerge": null, // Not merged yet
    "timeInReview": 52.3,
    "currentAge": 118.5,
    
    // Review Timestamps
    "firstReviewAt": "2026-02-10T19:00:00Z",
    "firstApprovalAt": "2026-02-12T18:45:00Z",
    "firstChangesRequestedAt": null,
    "latestReviewAt": "2026-02-14T16:00:00Z",
    
    // Status Flags
    "isStale": false,
    "needsReview": false,
    "hasConflicts": false,
    "hasCIFailures": false,
    
    // Risk Flags
    "riskFlags": [
      {
        "type": "large_pr",
        "severity": "medium",
        "message": "PR has 450 additions across 12 files"
      }
    ]
  },
  
  // Timestamps
  "factCreatedAt": "2026-02-15T14:00:00Z",
  "factUpdatedAt": "2026-02-15T14:00:00Z",
  "factCreatedAtEpoch": 1771185600,
  "factUpdatedAtEpoch": 1771185600
}
```

### Delivery Flow Calculation

The `deliveryFlow` object is computed from PR lifecycle events:

#### **Time Metrics**

1. **Time to First Review** (`timeToFirstReview`)
   ```
   = firstReviewAt - createdAt
   ```
   Measures how quickly the team starts reviewing PRs.

2. **Time to First Approval** (`timeToFirstApproval`)
   ```
   = firstApprovalAt - createdAt
   ```
   Measures time to get initial approval.

3. **Time to Merge** (`timeToMerge`)
   ```
   = mergedAt - createdAt
   ```
   Total delivery time from PR creation to merge.

4. **Time in Review** (`timeInReview`)
   ```
   = (mergedAt OR now) - firstReviewAt
   ```
   How long PR spent in review state.

5. **Current Age** (`currentAge`)
   ```
   = now - createdAt
   ```
   How long the PR has been open.

#### **Status Flags**

- **`isStale`**: PR hasn't been updated in 7+ days
- **`needsReview`**: PR has pending review requests
- **`hasConflicts`**: Merge conflicts detected (`mergeable: false`)
- **`hasCIFailures`**: CI checks failing (`mergeableState: "unstable"`)

#### **Risk Flags**

Automatically detected risks:

```javascript
[
  {
    "type": "large_pr",
    "severity": "high",
    "message": "PR has 800+ additions - consider breaking it down"
  },
  {
    "type": "stale_pr",
    "severity": "medium", 
    "message": "PR hasn't been updated in 10 days"
  },
  {
    "type": "pending_reviews",
    "severity": "low",
    "message": "Awaiting approval from 2 reviewer(s)"
  },
  {
    "type": "ci_checks_failing",
    "severity": "high",
    "message": "CI checks are failing"
  },
  {
    "type": "merge_conflicts",
    "severity": "high",
    "message": "PR has merge conflicts"
  }
]
```

---

## GitHub API Parameters & Queries

### What the Agent Checks in GitHub

#### **1. Repository Events API**

**Endpoint:** `GET /repos/{owner}/{repo}/events`

**Parameters:**
- `per_page=100` - Fetch up to 100 recent events
- **No date filter** - Must filter client-side

**What's fetched:**
- Last ~100 events per repository
- Filtered by:
  - Actor (must match team member's GitHub username)
  - Event timestamp (must be within the day window)
  - Event type (PushEvent, PullRequestEvent, etc.)

**Example Request:**
```bash
GET https://api.github.com/repos/my-org/api-gateway/events?per_page=100
Authorization: Bearer ghp_xxxxxxxxxxxx
```

#### **2. Organization Events API** (Fallback)

**Endpoint:** `GET /orgs/{org}/events`

**Used when:** No specific repos are scoped

**Example Request:**
```bash
GET https://api.github.com/orgs/my-org/events?per_page=100
```

#### **3. Pull Request Search API**

**Endpoint:** `GET /search/issues`

**Purpose:** Find PRs updated in last 14 days

**Query Parameters:**
```javascript
// Basic query
`repo:my-org/api-gateway is:pr updated:>=2026-02-01`

// With branch filtering (specific branches)
`repo:my-org/api-gateway is:pr updated:>=2026-02-01 base:main base:develop`

// With wildcard branches (no base filter)
`repo:my-org/api-gateway is:pr updated:>=2026-02-01`
```

**Example Request:**
```bash
GET https://api.github.com/search/issues?q=repo:my-org/api-gateway+is:pr+updated:>=2026-02-01+base:main&per_page=50
```

#### **4. Pull Request Details API**

**Endpoint:** `GET /repos/{owner}/{repo}/pulls/{pr_number}`

**What's fetched:**
- PR metadata (title, description, state, labels)
- Base and head branches
- Author information
- Draft status
- Merge state and conflicts
- Requested reviewers
- Creation/update/merge timestamps

**Example Request:**
```bash
GET https://api.github.com/repos/my-org/api-gateway/pulls/123
```

#### **5. Pull Request Files API**

**Endpoint:** `GET /repos/{owner}/{repo}/pulls/{pr_number}/files`

**What's fetched:**
- List of changed files
- Additions/deletions per file
- File extensions and types
- Patch content (not stored)

**Parameters:**
- `per_page=100` - Limited to first 100 files

**Example Response:**
```json
[
  {
    "filename": "src/auth/jwt.js",
    "status": "modified",
    "additions": 45,
    "deletions": 12,
    "changes": 57
  }
]
```

#### **6. Pull Request Reviews API**

**Endpoint:** `GET /repos/{owner}/{repo}/pulls/{pr_number}/reviews`

**What's fetched:**
- All review submissions
- Review state (APPROVED, CHANGES_REQUESTED, COMMENTED)
- Reviewer information
- Submission timestamps

**Example Response:**
```json
[
  {
    "id": 123456,
    "user": { "login": "reviewer1" },
    "state": "APPROVED",
    "submitted_at": "2026-02-14T16:00:00Z"
  }
]
```

#### **7. Pull Request Comments API**

**Endpoint:** `GET /repos/{owner}/{repo}/issues/{pr_number}/comments`

**What's fetched:**
- All conversation comments (not review comments)
- Comment author
- Comment body (to detect @mentions)
- Comment timestamps

---

## User Metrics Storage

### GitHub Metrics Table Structure

**Table:** `zaph-github-metrics`

**Primary Key:**
- `PK`: `TENANT#tnt_xxx#PROJECT#proj_xxx#USER#user@example.com`
- `SK`: `DATE#2026-02-15`

**Example Record:**

```javascript
{
  "PK": "TENANT#tnt_xxx#PROJECT#proj_xxx#USER#john@example.com",
  "SK": "DATE#2026-02-15",
  
  // Identifiers
  "tenantId": "tnt_xxx",
  "projectId": "proj_xxx",
  "projectName": "Backend Services",
  "userEmail": "john@example.com",
  "userId": "user_xxx",
  "fullName": "John Doe",
  "githubUsername": "johndoe",
  
  // Date & Time
  "date": "2026-02-15",
  "timezone": "America/New_York",
  "windowStartUtc": "2026-02-15T05:00:00.000Z",
  "windowEndUtc": "2026-02-16T04:59:59.999Z",
  
  // Integration
  "integrationId": "PROVIDER#GITHUB#ORG",
  "provider": "github",
  "orgName": "my-org",
  
  // 📊 METRICS
  "commitsCount": 8,
  "prsOpened": 2,
  "prsMerged": 1,
  "prsReviewed": 3,
  "issuesOpened": 1,
  "issuesClosed": 2,
  "linesAdded": 450,
  "linesDeleted": 120,
  
  // Activity Score
  "activityScore": 28,  // Weighted: commits*1 + opened*3 + merged*5 + reviewed*2
  
  // 📁 REPOSITORIES
  "repos": [
    {
      "repoId": "12345",
      "repoName": "my-org/api-gateway",
      "commitsCount": 5,
      "prsOpened": 1,
      "prsMerged": 1,
      "prsReviewed": 2,
      "issuesOpened": 0,
      "issuesClosed": 1,
      "linesAdded": 300,
      "linesDeleted": 80
    },
    {
      "repoId": "67890",
      "repoName": "my-org/auth-service",
      "commitsCount": 3,
      "prsOpened": 1,
      "prsMerged": 0,
      "prsReviewed": 1,
      "issuesOpened": 1,
      "issuesClosed": 1,
      "linesAdded": 150,
      "linesDeleted": 40
    }
  ],
  
  // 🔥 OPEN PULL REQUESTS
  "openPRs": [
    {
      "prNumber": 125,
      "prId": "98765",
      "prTitle": "feat: Add OAuth2 support",
      "prDescription": "Implements OAuth2 authentication flow...",
      "prType": "feature",
      "repoName": "my-org/auth-service",
      "url": "https://github.com/my-org/auth-service/pull/125",
      "state": "open",
      "isDraft": false,
      "createdAt": "2026-02-14T10:00:00Z",
      "lastUpdatedAt": "2026-02-15T14:30:00Z",
      "mergedAt": null,
      "hasBeenOpenForDays": 1.2,
      "wasOpenedToday": false,
      "wasMergedToday": false,
      
      // Code changes
      "additions": 150,
      "deletions": 40,
      "changedFiles": 6,
      "fileExtensions": ["js", "json"],
      "fileTypes": ["source_code", "config"],
      "labels": ["feature", "auth"],
      
      // Reviews
      "approvalCount": 0,
      "changesRequestedCount": 0,
      "requestedReviewers": [
        {
          "githubUsername": "reviewer1",
          "githubUserId": "789",
          "zaphUserEmail": "reviewer@example.com",
          "fullName": "Jane Smith",
          "requestedAt": "2026-02-14T10:00:00Z",
          "hasReviewed": false
        }
      ],
      
      // Blockers
      "blockers": [
        {
          "type": "pending_reviews",
          "details": "Awaiting approval from 1 reviewer(s)"
        }
      ],
      
      // Comments
      "commentSummary": {
        "totalComments": 3,
        "participants": ["johndoe", "tech-lead"],
        "mentionedUsers": ["@devops"],
        "unresolvedThreads": 1,
        "lastCommentAt": "2026-02-15T11:00:00Z",
        "conversationSummary": "Discussion about OAuth flow implementation"
      }
    }
  ],
  
  // 👥 PENDING REVIEWS
  "pendingReviewsFrom": [
    {
      "prNumber": 118,
      "prTitle": "refactor: Update database schema",
      "repoName": "my-org/api-gateway",
      "author": "other-dev",
      "url": "https://github.com/my-org/api-gateway/pull/118",
      "requestedAt": "2026-02-13T09:00:00Z",
      "prAge": 2.3
    }
  ],
  
  // 🚩 RISK FLAGS
  "riskFlags": [
    {
      "type": "large_pr",
      "severity": "medium",
      "prNumber": 125,
      "message": "PR #125 has 150 additions across 6 files"
    }
  ],
  
  // 🚧 BLOCKERS
  "blockers": [
    {
      "type": "pending_reviews",
      "prNumber": 125,
      "message": "PR #125 awaiting approval from 1 reviewer(s)"
    }
  ],
  
  // 🤖 AI SUMMARY
  "aiSummary": {
    "summary": "John made strong progress today on authentication features...",
    "keyAchievements": [
      "Completed OAuth2 integration for auth-service",
      "Fixed critical bug in JWT token validation",
      "Reviewed 3 PRs for team members"
    ],
    "blockers": [
      "PR #125 needs review approval to proceed"
    ],
    "nextSteps": [
      "Address feedback on OAuth2 implementation",
      "Start work on role-based access control"
    ],
    "sentiment": "productive",
    "detailedActivities": {
      "commits": "Pushed 8 commits across 2 repositories...",
      "pullRequests": "Opened 2 new PRs and merged 1...",
      "reviews": "Reviewed 3 PRs, providing detailed feedback...",
      "collaboration": "Active discussions on authentication approach..."
    }
  },
  
  // 📊 RAW STATISTICS
  "rawStats": {
    "eventsSampleCount": 45,
    "perRepoEventCounts": {
      "api-gateway": { "status": 200, "count": 28 },
      "auth-service": { "status": 200, "count": 17 }
    },
    "usedSearchFallback": false,
    "searchSummary": {
      "prSearchCount": 12,
      "issueSearchCount": 3,
      "errors": []
    },
    "reposQueried": ["api-gateway", "auth-service"]
  },
  
  // Timestamps
  "createdAt": "2026-02-15T14:00:00Z",
  "updatedAt": "2026-02-15T14:00:00Z",
  "createdAtEpoch": 1771185600,
  "updatedAtEpoch": 1771185600,
  
  // Job tracking
  "jobRunId": "job_1771185600123",
  "processingDuration": 8500,
  
  // Data quality
  "dataQuality": {
    "isValid": true,
    "qualityScore": 95,
    "issues": []
  }
}
```

---

## Time Window & Timezone Handling

### How Daily Windows Work

The agent supports timezone-aware daily windows:

```javascript
// Input
{
  "date": "2026-02-15",           // Target date
  "timezone": "America/New_York"  // User's timezone (optional)
}

// Computed Window
{
  "windowStartUtc": "2026-02-15T05:00:00.000Z",  // 00:00 EST
  "windowEndUtc": "2026-02-16T04:59:59.999Z"     // 23:59:59 EST
}
```

**Event Filtering:**
- Only events with `created_at` within this UTC window are counted
- Ensures daily metrics align with user's working day

**Supported Timezones:**
- `America/New_York` (EST/EDT)
- `America/Los_Angeles` (PST/PDT)
- `Europe/London` (GMT/BST)
- `Asia/Kolkata` (IST)
- And any IANA timezone identifier

---

## AI Summary Generation

### How Summaries Are Created

The agent uses **GPT-4** to generate natural language summaries:

#### **Input to AI:**
```javascript
{
  "userFullName": "John Doe",
  "date": "2026-02-15",
  "metrics": {
    "commitsCount": 8,
    "prsOpened": 2,
    "prsMerged": 1,
    // ... all metrics
  },
  "openPRs": [ /* PR details */ ],
  "pendingReviewsFrom": [ /* Reviews needed */ ],
  "blockers": [ /* Current blockers */ ],
  "riskFlags": [ /* Detected risks */ ],
  "last3DaysMetrics": { /* Trend data */ }
}
```

#### **AI Prompt:**
The agent sends a structured prompt asking GPT-4 to:
1. Summarize the day's achievements
2. Identify blockers and risks
3. Suggest next steps
4. Assess overall productivity sentiment

#### **Output Format:**
```javascript
{
  "summary": "Brief overview paragraph",
  "keyAchievements": ["Achievement 1", "Achievement 2"],
  "blockers": ["Blocker 1"],
  "nextSteps": ["Step 1", "Step 2"],
  "sentiment": "productive" | "slow" | "blocked",
  "detailedActivities": {
    "commits": "Detailed description...",
    "pullRequests": "Detailed description...",
    "reviews": "Detailed description...",
    "collaboration": "Detailed description..."
  }
}
```

---

## Environment Variables

Required configuration:

```bash
# DynamoDB Tables
CORE_TABLE_NAME=zaph-core
INTEGRATIONS_TABLE_NAME=zaph-integrations
GITHUB_METRICS_TABLE_NAME=zaph-github-metrics
DELIVERY_FACTS_TABLE_NAME=zaph-delivery-facts

# AWS Region
AWS_REGION=us-east-1

# Secrets Manager ARNs
GITHUB_APP_SECRET_ARN=arn:aws:secretsmanager:us-east-1:xxx:secret:/zaph/github/app-secret-xxx
DATA_MODEL_SECRET_ARN=arn:aws:secretsmanager:us-east-1:xxx:secret:zaph/data-model/json-secret-xxx

# OpenAI
OPENAI_API_KEY=sk-xxxxxxxxxxxxxxxx
```

---

## Event Payload Schema

### Lambda Invocation Event

```javascript
{
  "tenantId": "tnt_xxx",
  "projectId": "proj_xxx",
  "date": "2026-02-15",           // Optional, defaults to today
  "timezone": "America/New_York", // Optional, defaults to UTC
  "triggeredByUserId": "user_xxx", // Optional
  "triggeredByEmail": "admin@example.com", // Optional
  "jobRunId": "job_123456"        // Optional, auto-generated if missing
}
```

### Response Format

```javascript
{
  "statusCode": 200,
  "body": {
    "message": "Successfully processed GitHub metrics",
    "tenantId": "tnt_xxx",
    "projectId": "proj_xxx",
    "date": "2026-02-15",
    "membersProcessed": 5,
    "prFactsCreated": 12,
    "totalDuration": 45000,
    "correlationId": "corr_1771185600_xxx"
  }
}
```

---

## Error Handling & Circuit Breaker

### Circuit Breaker Pattern

Protects against cascading failures from GitHub API:

```javascript
{
  "state": "CLOSED",  // CLOSED, OPEN, HALF_OPEN
  "failures": 0,
  "threshold": 5,     // Open after 5 consecutive failures
  "cooldownMs": 60000 // Wait 1 minute before retry
}
```

**States:**
- **CLOSED**: Normal operation
- **OPEN**: Too many failures, reject all calls
- **HALF_OPEN**: Testing if service recovered

### Error Responses

**400 Bad Request:**
```javascript
{
  "error": "Input validation failed",
  "details": ["Missing or invalid tenantId"],
  "correlationId": "corr_xxx"
}
```

**500 Internal Error:**
```javascript
{
  "error": "Failed to process GitHub metrics",
  "message": "GitHub API rate limit exceeded",
  "correlationId": "corr_xxx"
}
```

---

## Performance Optimizations

### 1. **Parallel PR Fetching**
- Fetches multiple PRs concurrently (with rate limiting)
- 120ms delay between requests to avoid rate limits

### 2. **Event Filtering**
- Client-side filtering by date/user reduces processing
- Branch map lookup is O(1) using hash maps

### 3. **Caching**
- GitHub access tokens cached during execution
- Secrets fetched once per lambda invocation

### 4. **Data Quality Checks**
- Validates metrics before storage
- Logs quality scores for monitoring

---

## Logging & Monitoring

### Structured Logging

All logs use JSON format:

```javascript
{
  "level": "INFO",
  "message": "MEMBER_PROCESSING_START",
  "correlationId": "corr_1771185600_xxx",
  "githubUsername": "johndoe",
  "userEmail": "john@example.com",
  "date": "2026-02-15",
  "timestamp": "2026-02-15T14:00:00Z"
}
```

### Key Log Events

- `RUN_WINDOW_RESOLVED`: Daily window computed
- `MEMBER_PROCESSING_START`: Started processing user
- `METRICS_FETCHED`: Metrics collected successfully
- `DATA_QUALITY_BELOW_THRESHOLD`: Quality issues detected
- `AI_SUMMARY_GENERATED`: Summary created
- `PROCESSING_COMPLETE`: Job finished

---

## Common Use Cases

### 1. **Daily Standup Reports**
Triggered via EventBridge at 9 AM daily:
```javascript
{
  "tenantId": "tnt_xxx",
  "projectId": "proj_xxx",
  "timezone": "America/New_York"
}
```

### 2. **Historical Backfill**
Process metrics for a specific past date:
```javascript
{
  "tenantId": "tnt_xxx",
  "projectId": "proj_xxx",
  "date": "2026-02-10"
}
```

### 3. **Manager Analytics**
Automatically stores PR facts for:
- Delivery time analysis
- Review velocity tracking
- Bottleneck identification
- Team performance dashboards

---

## Limitations & Constraints

1. **GitHub API Rate Limits**
   - 5,000 requests/hour with GitHub App token
   - Circuit breaker prevents exhaustion

2. **Event History**
   - GitHub Events API returns ~100 recent events
   - Events older than 90 days are unavailable

3. **PR Files Limit**
   - Only first 100 changed files are analyzed
   - Very large PRs may have incomplete file data

4. **Branch Filtering**
   - Search API doesn't support multiple base branches efficiently
   - Wildcard (`*`) requires post-fetch filtering

5. **Processing Time**
   - ~5-10 seconds per team member
   - Lambda timeout should be 5+ minutes for large teams

---

## Summary

The GitHub AI Standup Agent is a comprehensive system that:

✅ **Collects** granular developer activity from GitHub  
✅ **Analyzes** PR delivery flow and identifies blockers  
✅ **Stores** detailed metrics and PR facts in DynamoDB  
✅ **Generates** AI-powered standup summaries with GPT-4  
✅ **Supports** fine-grained repo and branch scoping  
✅ **Handles** timezone-aware daily windows  
✅ **Provides** manager analytics via delivery facts  

This enables automated, data-driven standup reports that save time and provide actionable insights for development teams.
