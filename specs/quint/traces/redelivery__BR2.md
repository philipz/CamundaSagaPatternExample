**redelivery / BR2_noOrphanAfterCompensation**  
need=T+H

| # | event | phase | process status/ref | supplier active | open tasks |
|---|---|---|---|---|---|
| 0 | Started | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Train) |
| 1 | Fetched(Book(Train)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Train)🔒 |
| 2 | SideEffect(Book(Train)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{1} H:{} | Book(Train)🔒✔ |
| 3 | LockExpired(Book(Train)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{1} H:{} | Book(Train) |
| 4 | Fetched(Book(Train)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{1} H:{} | Book(Train)🔒 |
| 5 | SideEffect(Book(Train)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{1,2} H:{} | Book(Train)🔒✔ |
| 6 | Completed(Book(Train)) | Booking | F:–/0 T:Conf/2 H:–/0 | F:{} T:{1,2} H:{} | Book(Hotel) |
| 7 | Fetched(Book(Hotel)) | Booking | F:–/0 T:Conf/2 H:–/0 | F:{} T:{1,2} H:{} | Book(Hotel)🔒 |
| 8 | SideEffect(Book(Hotel)) | Booking | F:–/0 T:Conf/2 H:–/0 | F:{} T:{1,2} H:{3} | Book(Hotel)🔒✔ |
| 9 | Completed(Book(Hotel)) | Review | F:–/0 T:Conf/2 H:Conf/3 | F:{} T:{1,2} H:{3} | – |
| 10 | UserCanceled | Compensating | F:–/0 T:Conf/2 H:Conf/3 | F:{} T:{1,2} H:{3} | Cancel(Hotel), Cancel(Train) |
| 11 | Fetched(Cancel(Train)) | Compensating | F:–/0 T:Conf/2 H:Conf/3 | F:{} T:{1,2} H:{3} | Cancel(Hotel), Cancel(Train)🔒 |
| 12 | SideEffect(Cancel(Train)) | Compensating | F:–/0 T:Conf/2 H:Conf/3 | F:{} T:{1} H:{3} | Cancel(Hotel), Cancel(Train)🔒✔ |
| 13 | Completed(Cancel(Train)) | Compensating | F:–/0 T:Canc/2 H:Conf/3 | F:{} T:{1} H:{3} | Cancel(Hotel) |
| 14 | Fetched(Cancel(Hotel)) | Compensating | F:–/0 T:Canc/2 H:Conf/3 | F:{} T:{1} H:{3} | Cancel(Hotel)🔒 |
| 15 | SideEffect(Cancel(Hotel)) | Compensating | F:–/0 T:Canc/2 H:Conf/3 | F:{} T:{1} H:{} | Cancel(Hotel)🔒✔ |
| 16 | Completed(Cancel(Hotel)) | Review | F:–/0 T:Canc/2 H:Canc/3 | F:{} T:{1} H:{} | – |
