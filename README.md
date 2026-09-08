# 🧠 Accounting Database System (PostgreSQL)

A modular **Accounting database system** designed to handle inventory, sales, and financial transactions and more using PostgreSQL.

---

## 🚀 Features

* 💰 **Accounting System**

  * Double-entry bookkeeping (Debit/Credit)
  * Automatic journal entry generation

* 🧾 **Accounts Receivable**

  * Tracks customer balances and supplier obligations
  * Supports payment status and due dates

* 🥞 **Multitenant client and Chart of Account**

  * Multiple Clients can simultaneously operate 
  * Multiple Chart of account custom made for every Clients needs

* 🧩 **Partitioned Tables**

  * Scalable handling of financial data using date-based partitioning

* 🫆 **Audit Logs / Extended Audit Logs**

  * Audit Hash Code Chain
  * Automatic Recording Every Transaction
  * Summary Import Logs

* 📋 **Audit Trail**
 
  * Transaction Life Cycle
  * Import Session

* 📝 **Compliance**
  
  * Compliance log
  * import compliance log

* 🗂 **Staging**
  
   * Data Testing
   * Sanitation
   * Validation
   * Approval
    
* 🛡️ **Trigger Guard**

   * Prevent direct operation to table
   * Need specific setting to perform CRUD Operations

---

## 🏗️ System Architecture

```

[CSV/ API/ SPREAD_SHEET_IMPORT]
   
   
    ↓ ---------------> [log the import details in summary and every succes/fail transaction]


[Staging] ----------------> [log to import workflows status]
   

    ↓ ---------------> [update the import workflow status]


[Sanitation] ----------------> [Record Lineage] 
   

    ↓ ----------------> [update the import workflow status]


[Validations] ----------------> [Record Lineage]
   

    ↓ ----------------> [update the workflow status]


[Approval Chain] ----------------> [Record Lineage]


    ↓ ----------------> [update the workflow status]


[Posting] ----------------> [Record Lineage]
   
   
    ↓ ----------------> [update the workflow status and import workflow end here]


    ↓ ----------------> [Trigger guard work on this part to prevent by passing or cut the process]


[ AR / AP / Inventory Transactions and so on] ----------------> [Record Lineage, Audit Log, and transaction lifecycle] 
      

    ↓ ----------------> [Trigger guard work on this part to prevent by passing or cut the process]


[Journals] -> [Audit Log/ update transaction life cycle]    


    ↓ ----------------> [Trigger guard work on this part to prevent by passing or cut the process]


[Accounting Module/Inventory Module] ----------------> [Audit Log]


    ↓ ----------------> [Trigger guard work on this part to prevent by passing or cut the process]


[Validations at core production] ----------------> [Record Lineage]


    ↓ ----------------> [update the transaction life cycle status]


[Approval Chain at core production ] ----------------> [Record Lineage]


    ↓ ----------------> [update the transaction life cycle status]


[Transaction business/reports/reconcile]


    ↓


[Archive( 12 months)]

```

## 🚀 Environment Setup (Ubuntu)

### 🔄 Update System

```bash
sudo apt update
sudo apt upgrade -y
```

## 🐳 Install Docker

```bash
sudo apt install apt-transport-https ca-certificates curl software-properties-common -y

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

sudo add-apt-repository \
"deb [arch=amd64] https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable"

sudo apt install docker-ce docker-ce-cli containerd.io -y
```

## Install Docker Composer
```bash
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

sudo chmod +x /usr/local/bin/docker-compose
```

### ▶️ Enable Docker
```bash
sudo systemctl enable docker
sudo systemctl start docker

sudo usermod -aG docker $USER
newgrp docker
```
### 📁 Create Mount Points
```bash
sudo mkdir /mnt/ssd_hot
sudo mkdir /mnt/hdd_cold
sudo chown postgres:postgres /mnt/ssd_hot /mnt/hdd_cold
sudo chmod 700 /mnt/ssd_hot /mnt/hdd_cold
```

### 🔗 Mount Drives
```bash
mount {ssd_location} /mnt/ssd_hot
mount {hdd_location} /mnt/hdd_cold
```

### 🧠 Create Tablespaces

Inside container:

```sql
CREATE TABLESPACE hotspace LOCATION '/mnt/ssd_hot';
CREATE TABLESPACE coldspace LOCATION '/mnt/hdd_cold';
```


### 🔥 Fire wall 🔥
```bash

sudo apt install ufw

sudo ufw enable
sudo ufw allow ssh
sudo ufw deny 5432
```

### 🔐 Use Environment File (DON’T hardcode passwords)
Create .env file:
```bash
nano .env
```

```bash
POSTGRES_PASSWORD=StrongPassword123!
POSTGRES_DB=erp_db
POSTGRES_USER=erp_admin
```

### 💾 Backup Setup (DO THIS NOW)

Create backup script:
```bash
nano backup.sh
```

```bash
#!/bin/bash
docker exec erp_postgres pg_dump -U erp_admin erp_db > /backup/erp_$(date +%F).sql
```
#### Make executable:
```bash
chmod +x backup.sh
```

#### Schedule daily backup:
```bash
crontab -e
```
Add:
```bash
7 2 * * * ~/git/Prod-database/backup.sh
```

### 🔐 Access PostgreSQL
```bash
docker exec -it erp_postgres psql -U erp_admin -d erp_db
```

Basic Performance Config Inside container:
```bash
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET work_mem = '4MB';
SELECT pg_reload_conf();
```

### Some Helpful Debuging commands

let's debug this systematically. Run these commands:

1. Check if container is running
```bash
docker ps | grep erp_postgres
```
2. Check initialization logs
```bash
docker logs erp_postgres
```
Look for error messages or initialization output.
3. Verify volume is mounted correctly
```bash
docker exec erp_postgres ls -la /docker-entrypoint-initdb.d/
Should show your .sql files.
```
4. Check if database was created
```bash
docker exec erp_postgres psql -U postgres -l
Should list erp_db if initialization ran.
```
5. Force fresh initialization
```bash
docker-compose down -v
docker-compose up -d
docker logs erp_postgres
```
6. docker compose <yaml is at docker/>
```bash
docker composer -f docker/docker-composer.prod.yaml up
```
### Use sample data at tmp/data
```bash
  docker exec -i erp_postgres psql -U erp_admin -d erp_db < temp/data/data_sample.sql
```


## 🏗️ Repository Structure

```
accounting-database/

├── conf/ ---> Configuration setting of  dev enviroment, prod enviroment, and staging enviroment
      
├── doc/ ---> Documentation of feature and command list.

├── docker/ ---> Docker compose configuration files 

├── migration/ ---> List of new Feature script files    

├── schema/ ---> Core Transaction

├── script/ ---> Backup and Python script

├── staging/ ---> Testing and staging script for new feature 

├── tmp/ ---> Sample Data and Sample script files 

├── env.dev ---> dev enviroments credentials 

├── env.prod ---> prod enviroments credentials 

├── env.stagin ---> staging enviroments credentials 

├── ARCHITECTURE.md

├── IMPORT STAGING WORKFLOW.md

├── NAMING AND CODE FORMAT.md

├── OPERATION.md

├── SETUP.md

└── README.md

```
---

## 🧠 Key Concepts Demonstrated

* Relational Database Design (Normalization, Constraints)
* Partitioning Strategy (Range Partitioning by Date)
* Composite Keys in Partitioned Tables
* Foreign Key Integrity across modules
* Financial Data Modeling (ERP-style logic)
* Query Optimization using Indexes
* Modular Stored Procedure Design
* Audit Logs for Every success Operations
* Recording Data Lineage (From Staging to Production)
* Idempotency key for avoid duplicate transactions
* Code Hashing Chain to spot tampering
* Sanitation, Validation and Approval Chain at Staging 
* Trigger Guard Prevent bypassing validation and ensures every transaction follow the approved workflow

---

## 💼 Business Value

This system simulates a real Accounting backend where:

* Inventory transactions automatically affect financial records
* Sales generate accounts receivable
* Purchases generate accounts payable
* Financial reports can be derived from journal entries
* Record Data Lineage From Staging to Production to Archive
* Multiple Tenant and custom made Chart of Account
* Logs like Import, Audit, and Compliance
* Security (Idempotency key, Hash Chain, and Trigger Guard)
* Staging area (Sanitation, Validations and Approval)
* Transaction Lifecycle status tracking
  
---

## 📌 Road Map
```
CORE DATABASE DEVELOPMENT
        │
        ├── SQL / PostgreSQL
        ├── Data Modeling
        ├── PL/pgSQL
        ├── Indexes
        ├── Partitioning
        ├── Transactions
        │
        ↓
SECURITY
        │
        ├── RBAC
        ├── RLS
        ├── Auditing
        ├── SECURITY DEFINER
        └── search_path
        │
        ↓
BACKUP / RECOVERY
        │
        ├── Base Backup
        ├── WAL
        ├── Archiving
        ├── PITR
        └── Bash + Cron
        │
        ↓
⭐ PERFORMANCE / MAINTENANCE 
        │
        ├── VACUUM
        ├── ANALYZE
        ├── Autovacuum
        ├── EXPLAIN
        ├── Query Optimization
        ├── Index Optimization
        ├── Locks / Blocking
        └── Monitoring
        │
        ↓
DATA WAREHOUSING  ← NEXT
        │
        ├── Dimensional Modeling
        ├── Star Schema
        ├── ETL / ELT
        ├── SCD
        └── Incremental Loads
        │
        ↓
DATA ENGINEERING / CLOUD

---
```

Follow up things todo: install Open SSL create certification and key.
