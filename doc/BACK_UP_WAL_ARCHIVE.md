# Postgresql 15.17 Base Back Up and PITR

###pg_hba.con 

    make sure this is coded
```
TYPE  DATABASE        USER            ADDRESS                 METHOD
local   replication     <any_user>                               trust
```
### yaml 
the very reason for this is we create and mount the WAL archive to Volume wal_arche : /var/lib/postgresql/wal_archive
that is why we need to give persimision to it.
```
   volumes:
      - pgdata:/var/lib/postgresql/data
      - wal_archive:/var/lib/postgresql/wal_archive
```

### postgres.conf
make sure it was comment at first and then undo it when recovery is needed
  ```
  # ===== RECOVERY SETTINGS =====
  #restore_command = 'cp /var/lib/postgresql/wal_archive/%f %p'
  #recovery_target_time = '2026-08-12 15:05:00'  # <-- CHANGE THIS to your Baseline Time
  #recovery_target_action = 'promote'
  #recovery_target_inclusive = 'true'
 ```
plus make sure of this
 ```
  # Archiving
  wal_level = replica
  archive_mode = on
  archive_command = 'cp %p /var/lib/postgresql/wal_archive/%f'
```
### Run the environment (production, staging, or env)
```
docker-compose -f ./docker/docker-compose.prod.yml -p production up

## Throw error to fix :

docker exec -it erp_postgres chown postgres:postgres /var/lib/postgresql/wal_archive

docker exec -it erp_postgres chmod 700 /var/lib/postgresql/wal_archive
```

### For Checking 
  restart it first:
```
  docker restart erp_postgres
```
### then check for wal that start with 0000000000000000000000000001
```
  docker exec -it erp_postgres ls -lh /var/lib/postgresql/wal_archive
```
### execute this is for sample data for testing 
  ```
  docker exec -i erp_postgres psql -U erp_admin -d erp_db < ./tmp/DATA/data_sample.sql
```
### make a base back up 
### make sure the permision is right
```
  ./script/basebackup.sh
```
```  
docker exec -it erp_postgres psql -U erp_admin -d erp_db -c "SELECT pg_switch_wal();"
```
### lets break thing
```  
  docker exec -it erp_postgres psql -U erp_admin -d erp_db -c "DROP TABLE finance.products CASCADE;" 2026-08-12 18:16:49
```
### wait for about 3 minute
  ```
  docker exec -it erp_postgres psql -U erp_admin -d erp_db -c "DROP TABLE finance.customers CASCADE;"  2026-08-12 18:21:22
```
### look at the logs and get the time when they executed
```  
  docker logs erp_postgre -f
```
### dont down the container yet! first delete _data direcotry
```  
  docker exec -it erp_postgres bash
  rm -rf /var/lib/postgresql/data/*
```
### WARNING! this is critical make this sure.
### Fix permissions (Crucial!)
 ``` 
  sudo chown -R 999:999 /var/lib/docker/volumes/erp_postgres_pgdata/_data
```
### this is the time to down the container then create recovery.signal
```  
  sudo touch /var/lib/docker/volumes/erp_postgres_pgdata/_data/recovery.signal

  sudo chown 999:999 /var/lib/docker/volumes/erp_postgres_pgdata/_data/recovery.signal
```
### restore the _data from backup look for the newest back with few step to follow bear with me!
  1. create directory restore
  2. Extract the backup files : tar -xzf /backup/basebackup.tar.gz
  3. then another directory to comes change the owner
  4. access it then and  look for base.tar.gz then extract it again tar -xzf 
  5. make sure its on the restore directory created earlier: sudo chown -R 999:999 ./*
  6. final move it /var/lib/docker/volumes/erp_postgres_pgdata/_data : sudo mv ./restore/* /var/lib/docker/volumes/erp_postgres_pgdata/_data

### postgres.conf uncomment then provide the recovery target time 
  # ===== RECOVERY SETTINGS =====
  restore_command = 'cp /var/lib/postgresql/wal_archive/%f %p'
  recovery_target_time = '2026-08-12 15:05:00'  # <-- CHANGE THIS to your Baseline Time
  recovery_target_action = 'promote'
  recovery_target_inclusive = 'true'

### Finally
  up the container and restart it 

### Atlast have some proper sleeps. Well because I do need it!

### Trouble shooting command that are might be very useful

#### check archive 
  docker exec -it erp_postgres ls -ld /var/lib/postgresql/wal_archive 
  docker exec -it erp_postgres ls -lh /var/lib/postgresql/wal_archive

### wal and archive
  docker exec -it erp_postgres psql -U erp_admin -d erp_db -c "SELECT pg_switch_wal();"
  docker exec -it erp_postgres psql -U erp_admin -d erp_db -c "SHOW archive_mode;"
  docker exec -it erp_postgres psql -U erp_admin -d erp_db -c "SELECT pg_switch_wal(); CHECKPOINT;"
  docker exec -it erp_postgres psql -U erp_admin -d erp_db -c "SELECT pg_switch_wal();"

### browsing history 
  docker logs erp_postgres
  docker-compose logs postgres | grep -iE "(error|warning|recovery|restore|target)"

### volume file location and information
sudo ls -al /var/lib/docker/volumes/erp_postgres_wal_archive/_data
sudo ls -al /var/lib/docker/volumes/erp_postgres_pgdata/_data

# Copy your backup contents into the empty volume
sudo cp -r /path/to/your/new_backup/* /var/lib/docker/volumes/erp_postgres_pgdata/_data/
