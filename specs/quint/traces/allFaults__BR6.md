**allFaults / BR6_cancelTargetsRealBooking**  
need=F+H; supplier down=T; cancel refused=H

| # | event | phase | process status/ref | supplier active | open tasks |
|---|---|---|---|---|---|
| 0 | Started | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight) |
| 1 | Fetched(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight)🔒 |
| 2 | HandlerFailed(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight) |
| 3 | Fetched(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight)🔒 |
| 4 | HandlerFailed(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight) |
| 5 | Fetched(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight)🔒 |
| 6 | SideEffect(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Flight)🔒✔ |
| 7 | LockExpired(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Flight) |
| 8 | Fetched(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Flight)🔒 |
| 9 | SideEffect(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1,3} T:{} H:{} | Book(Flight)🔒✔ |
| 10 | Completed(Book(Flight)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{} | Book(Hotel) |
| 11 | Fetched(Book(Hotel)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{} | Book(Hotel)🔒 |
| 12 | HandlerFailed(Book(Hotel)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{} | Book(Hotel) |
| 13 | Fetched(Book(Hotel)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{} | Book(Hotel)🔒 |
| 14 | HandlerFailed(Book(Hotel)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{} | Book(Hotel) |
| 15 | Fetched(Book(Hotel)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{} | Book(Hotel)🔒 |
| 16 | HandlerFailed(Book(Hotel)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{} | Book(Hotel) |
| 17 | Fetched(Book(Hotel)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{} | Book(Hotel)🔒 |
| 18 | SideEffect(Book(Hotel)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{5} | Book(Hotel)🔒✔ |
| 19 | Completed(Book(Hotel)) | Review | F:Conf/4 T:–/0 H:Conf/5 | F:{1,3} T:{} H:{5} | – |
| 20 | UserCanceled | Compensating | F:Conf/4 T:–/0 H:Conf/5 | F:{1,3} T:{} H:{5} | Cancel(Flight), Cancel(Hotel) |
| 21 | Fetched(Cancel(Hotel)) | Compensating | F:Conf/4 T:–/0 H:Conf/5 | F:{1,3} T:{} H:{5} | Cancel(Flight), Cancel(Hotel)🔒 |
| 22 | Fetched(Cancel(Flight)) | Compensating | F:Conf/4 T:–/0 H:Conf/5 | F:{1,3} T:{} H:{5} | Cancel(Flight)🔒, Cancel(Hotel)🔒 |
| 23 | SideEffect(Cancel(Flight)) | Compensating | F:Conf/4 T:–/0 H:Conf/5 | F:{1,3} T:{} H:{5} | Cancel(Flight)🔒✔, Cancel(Hotel)🔒 |
| 24 | Completed(Cancel(Flight)) | Compensating | F:Canc/4 T:–/0 H:Conf/5 | F:{1,3} T:{} H:{5} | Cancel(Hotel)🔒 |
