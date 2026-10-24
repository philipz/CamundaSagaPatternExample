**cancelFailure / BR1_confirmedEndIsFullyBooked**  
need=F+H; cancel refused=T

| # | event | phase | process status/ref | supplier active | open tasks |
|---|---|---|---|---|---|
| 0 | Started | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight) |
| 1 | Fetched(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight)🔒 |
| 2 | SideEffect(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Flight)🔒✔ |
| 3 | Completed(Book(Flight)) | Booking | F:Conf/1 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Hotel) |
| 4 | Fetched(Book(Hotel)) | Booking | F:Conf/1 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Hotel)🔒 |
| 5 | SideEffect(Book(Hotel)) | Booking | F:Conf/1 T:–/0 H:–/0 | F:{1} T:{} H:{2} | Book(Hotel)🔒✔ |
| 6 | Completed(Book(Hotel)) | Review | F:Conf/1 T:–/0 H:Conf/2 | F:{1} T:{} H:{2} | – |
| 7 | UserCanceled | Compensating | F:Conf/1 T:–/0 H:Conf/2 | F:{1} T:{} H:{2} | Cancel(Flight), Cancel(Hotel) |
| 8 | Fetched(Cancel(Hotel)) | Compensating | F:Conf/1 T:–/0 H:Conf/2 | F:{1} T:{} H:{2} | Cancel(Flight), Cancel(Hotel)🔒 |
| 9 | SideEffect(Cancel(Hotel)) | Compensating | F:Conf/1 T:–/0 H:Conf/2 | F:{1} T:{} H:{} | Cancel(Flight), Cancel(Hotel)🔒✔ |
| 10 | Completed(Cancel(Hotel)) | Compensating | F:Conf/1 T:–/0 H:Canc/2 | F:{1} T:{} H:{} | Cancel(Flight) |
| 11 | Fetched(Cancel(Flight)) | Compensating | F:Conf/1 T:–/0 H:Canc/2 | F:{1} T:{} H:{} | Cancel(Flight)🔒 |
| 12 | HandlerFailed(Cancel(Flight)) | Compensating | F:Conf/1 T:–/0 H:Canc/2 | F:{1} T:{} H:{} | Cancel(Flight) |
| 13 | Fetched(Cancel(Flight)) | Compensating | F:Conf/1 T:–/0 H:Canc/2 | F:{1} T:{} H:{} | Cancel(Flight)🔒 |
| 14 | HandlerFailed(Cancel(Flight)) | Compensating | F:Conf/1 T:–/0 H:Canc/2 | F:{1} T:{} H:{} | Cancel(Flight) |
| 15 | Fetched(Cancel(Flight)) | Compensating | F:Conf/1 T:–/0 H:Canc/2 | F:{1} T:{} H:{} | Cancel(Flight)🔒 |
| 16 | HandlerFailed(Cancel(Flight)) | Compensating | F:Conf/1 T:–/0 H:Canc/2 | F:{1} T:{} H:{} | Cancel(Flight) |
| 17 | Fetched(Cancel(Flight)) | Compensating | F:Conf/1 T:–/0 H:Canc/2 | F:{1} T:{} H:{} | Cancel(Flight)🔒 |
| 18 | HandlerFailed(Cancel(Flight)) | Compensating | F:Conf/1 T:–/0 H:Canc/2 | F:{1} T:{} H:{} | Cancel(Flight) |
| 19 | Fetched(Cancel(Flight)) | Compensating | F:Conf/1 T:–/0 H:Canc/2 | F:{1} T:{} H:{} | Cancel(Flight)🔒 |
| 20 | HandlerFailed(Cancel(Flight)) | Compensating | F:Conf/1 T:–/0 H:Canc/2 | F:{1} T:{} H:{} | Cancel(Flight) |
| 21 | Fetched(Cancel(Flight)) | Compensating | F:Conf/1 T:–/0 H:Canc/2 | F:{1} T:{} H:{} | Cancel(Flight)🔒 |
| 22 | HandlerFailed(Cancel(Flight)) | Compensating | F:Conf/1 T:–/0 H:Canc/2 | F:{1} T:{} H:{} | Cancel(Flight) |
| 23 | Fetched(Cancel(Flight)) | Compensating | F:Conf/1 T:–/0 H:Canc/2 | F:{1} T:{} H:{} | Cancel(Flight)🔒 |
| 24 | HandlerFailed(Cancel(Flight)) | Compensating | F:Conf/1 T:–/0 H:Canc/2 | F:{1} T:{} H:{} | Cancel(Flight) |
| 25 | Fetched(Cancel(Flight)) | Compensating | F:Conf/1 T:–/0 H:Canc/2 | F:{1} T:{} H:{} | Cancel(Flight)🔒 |
| 26 | HandlerFailed(Cancel(Flight)) | Compensating | F:Conf/1 T:–/0 H:Canc/2 | F:{1} T:{} H:{} | Cancel(Flight) |
| 27 | Fetched(Cancel(Flight)) | Compensating | F:Conf/1 T:–/0 H:Canc/2 | F:{1} T:{} H:{} | Cancel(Flight)🔒 |
| 28 | SideEffect(Cancel(Flight)) | Compensating | F:Conf/1 T:–/0 H:Canc/2 | F:{} T:{} H:{} | Cancel(Flight)🔒✔ |
| 29 | Completed(Cancel(Flight)) | Review | F:Canc/1 T:–/0 H:Canc/2 | F:{} T:{} H:{} | – |
| 30 | UserConfirmed | Ended | F:Canc/1 T:–/0 H:Canc/2 | F:{} T:{} H:{} | – |
