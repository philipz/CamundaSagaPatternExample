**asIs / BR7_endIsAllOrNothing**  
need=F+T+H

| # | event | phase | process status/ref | supplier active | open tasks |
|---|---|---|---|---|---|
| 0 | Started | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight), Book(Train) |
| 1 | Fetched(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight)🔒, Book(Train) |
| 2 | Fetched(Book(Train)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight)🔒, Book(Train)🔒 |
| 3 | SideEffect(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Flight)🔒✔, Book(Train)🔒 |
| 4 | SideEffect(Book(Train)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{3} H:{} | Book(Flight)🔒✔, Book(Train)🔒✔ |
| 5 | Completed(Book(Train)) | Booking | F:–/0 T:Conf/3 H:–/0 | F:{1} T:{3} H:{} | Book(Flight)🔒✔ |
| 6 | Completed(Book(Flight)) | Booking | F:Conf/2 T:Conf/3 H:–/0 | F:{1} T:{3} H:{} | Book(Hotel) |
| 7 | Fetched(Book(Hotel)) | Booking | F:Conf/2 T:Conf/3 H:–/0 | F:{1} T:{3} H:{} | Book(Hotel)🔒 |
| 8 | SideEffect(Book(Hotel)) | Booking | F:Conf/2 T:Conf/3 H:–/0 | F:{1} T:{3} H:{4} | Book(Hotel)🔒✔ |
| 9 | Completed(Book(Hotel)) | Review | F:Conf/2 T:Conf/3 H:Conf/4 | F:{1} T:{3} H:{4} | – |
| 10 | UserConfirmed | Ended | F:Conf/2 T:Conf/3 H:Conf/4 | F:{1} T:{3} H:{4} | – |
