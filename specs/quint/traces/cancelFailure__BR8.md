**cancelFailure / BR8_neverStuckHoldingBookings**  
need=F+T+H; cancel refused=F+T+H

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
