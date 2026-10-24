**ideal / BR1_confirmedEndIsFullyBooked**  
need=F+T+H

| # | event | phase | process status/ref | supplier active | open tasks |
|---|---|---|---|---|---|
| 0 | Started | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight), Book(Train) |
| 1 | Fetched(Book(Train)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight), Book(Train)🔒 |
| 2 | Fetched(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight)🔒, Book(Train)🔒 |
| 3 | SideEffect(Book(Train)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{1} H:{} | Book(Flight)🔒, Book(Train)🔒✔ |
| 4 | Completed(Book(Train)) | Booking | F:–/0 T:Conf/1 H:–/0 | F:{} T:{1} H:{} | Book(Flight)🔒 |
| 5 | SideEffect(Book(Flight)) | Booking | F:–/0 T:Conf/1 H:–/0 | F:{2} T:{1} H:{} | Book(Flight)🔒✔ |
| 6 | Completed(Book(Flight)) | Booking | F:Conf/2 T:Conf/1 H:–/0 | F:{2} T:{1} H:{} | Book(Hotel) |
| 7 | Fetched(Book(Hotel)) | Booking | F:Conf/2 T:Conf/1 H:–/0 | F:{2} T:{1} H:{} | Book(Hotel)🔒 |
| 8 | SideEffect(Book(Hotel)) | Booking | F:Conf/2 T:Conf/1 H:–/0 | F:{2} T:{1} H:{3} | Book(Hotel)🔒✔ |
| 9 | Completed(Book(Hotel)) | Review | F:Conf/2 T:Conf/1 H:Conf/3 | F:{2} T:{1} H:{3} | – |
| 10 | UserCanceled | Compensating | F:Conf/2 T:Conf/1 H:Conf/3 | F:{2} T:{1} H:{3} | Cancel(Flight), Cancel(Hotel), Cancel(Train) |
| 11 | Fetched(Cancel(Hotel)) | Compensating | F:Conf/2 T:Conf/1 H:Conf/3 | F:{2} T:{1} H:{3} | Cancel(Flight), Cancel(Hotel)🔒, Cancel(Train) |
| 12 | Fetched(Cancel(Flight)) | Compensating | F:Conf/2 T:Conf/1 H:Conf/3 | F:{2} T:{1} H:{3} | Cancel(Flight)🔒, Cancel(Hotel)🔒, Cancel(Train) |
| 13 | Fetched(Cancel(Train)) | Compensating | F:Conf/2 T:Conf/1 H:Conf/3 | F:{2} T:{1} H:{3} | Cancel(Flight)🔒, Cancel(Hotel)🔒, Cancel(Train)🔒 |
| 14 | SideEffect(Cancel(Train)) | Compensating | F:Conf/2 T:Conf/1 H:Conf/3 | F:{2} T:{} H:{3} | Cancel(Flight)🔒, Cancel(Hotel)🔒, Cancel(Train)🔒✔ |
| 15 | SideEffect(Cancel(Flight)) | Compensating | F:Conf/2 T:Conf/1 H:Conf/3 | F:{} T:{} H:{3} | Cancel(Flight)🔒✔, Cancel(Hotel)🔒, Cancel(Train)🔒✔ |
| 16 | Completed(Cancel(Flight)) | Compensating | F:Canc/2 T:Conf/1 H:Conf/3 | F:{} T:{} H:{3} | Cancel(Hotel)🔒, Cancel(Train)🔒✔ |
| 17 | SideEffect(Cancel(Hotel)) | Compensating | F:Canc/2 T:Conf/1 H:Conf/3 | F:{} T:{} H:{} | Cancel(Hotel)🔒✔, Cancel(Train)🔒✔ |
| 18 | Completed(Cancel(Hotel)) | Compensating | F:Canc/2 T:Conf/1 H:Canc/3 | F:{} T:{} H:{} | Cancel(Train)🔒✔ |
| 19 | Completed(Cancel(Train)) | Review | F:Canc/2 T:Canc/1 H:Canc/3 | F:{} T:{} H:{} | – |
| 20 | UserConfirmed | Ended | F:Canc/2 T:Canc/1 H:Canc/3 | F:{} T:{} H:{} | – |
