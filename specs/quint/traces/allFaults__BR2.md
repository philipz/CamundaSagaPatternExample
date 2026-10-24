**allFaults / BR2_noOrphanAfterCompensation**  
need=H; supplier down=F; cancel refused=F

| # | event | phase | process status/ref | supplier active | open tasks |
|---|---|---|---|---|---|
| 0 | Started | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Hotel) |
| 1 | Fetched(Book(Hotel)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Hotel)🔒 |
| 2 | SideEffect(Book(Hotel)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{1} | Book(Hotel)🔒✔ |
| 3 | LockExpired(Book(Hotel)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{1} | Book(Hotel) |
| 4 | Fetched(Book(Hotel)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{1} | Book(Hotel)🔒 |
| 5 | SideEffect(Book(Hotel)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{1,2} | Book(Hotel)🔒✔ |
| 6 | LockExpired(Book(Hotel)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{1,2} | Book(Hotel) |
| 7 | Fetched(Book(Hotel)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{1,2} | Book(Hotel)🔒 |
| 8 | SideEffect(Book(Hotel)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{1,2,3} | Book(Hotel)🔒✔ |
| 9 | Completed(Book(Hotel)) | Review | F:–/0 T:–/0 H:Conf/3 | F:{} T:{} H:{1,2,3} | – |
| 10 | UserCanceled | Compensating | F:–/0 T:–/0 H:Conf/3 | F:{} T:{} H:{1,2,3} | Cancel(Hotel) |
| 11 | Fetched(Cancel(Hotel)) | Compensating | F:–/0 T:–/0 H:Conf/3 | F:{} T:{} H:{1,2,3} | Cancel(Hotel)🔒 |
| 12 | HandlerFailed(Cancel(Hotel)) | Compensating | F:–/0 T:–/0 H:Conf/3 | F:{} T:{} H:{1,2,3} | Cancel(Hotel) |
| 13 | Fetched(Cancel(Hotel)) | Compensating | F:–/0 T:–/0 H:Conf/3 | F:{} T:{} H:{1,2,3} | Cancel(Hotel)🔒 |
| 14 | HandlerFailed(Cancel(Hotel)) | Compensating | F:–/0 T:–/0 H:Conf/3 | F:{} T:{} H:{1,2,3} | Cancel(Hotel) |
| 15 | Fetched(Cancel(Hotel)) | Compensating | F:–/0 T:–/0 H:Conf/3 | F:{} T:{} H:{1,2,3} | Cancel(Hotel)🔒 |
| 16 | HandlerFailed(Cancel(Hotel)) | Compensating | F:–/0 T:–/0 H:Conf/3 | F:{} T:{} H:{1,2,3} | Cancel(Hotel) |
| 17 | Fetched(Cancel(Hotel)) | Compensating | F:–/0 T:–/0 H:Conf/3 | F:{} T:{} H:{1,2,3} | Cancel(Hotel)🔒 |
| 18 | SideEffect(Cancel(Hotel)) | Compensating | F:–/0 T:–/0 H:Conf/3 | F:{} T:{} H:{1,2} | Cancel(Hotel)🔒✔ |
| 19 | Completed(Cancel(Hotel)) | Review | F:–/0 T:–/0 H:Canc/3 | F:{} T:{} H:{1,2} | – |
