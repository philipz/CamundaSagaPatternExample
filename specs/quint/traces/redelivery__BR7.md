**redelivery / BR7_endIsAllOrNothing**  
need=F+H

| # | event | phase | process status/ref | supplier active | open tasks |
|---|---|---|---|---|---|
| 0 | Started | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight) |
| 1 | Fetched(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight)🔒 |
| 2 | SideEffect(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Flight)🔒✔ |
| 3 | Completed(Book(Flight)) | Booking | F:Conf/1 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Hotel) |
| 4 | Fetched(Book(Hotel)) | Booking | F:Conf/1 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Hotel)🔒 |
| 5 | SideEffect(Book(Hotel)) | Booking | F:Conf/1 T:–/0 H:–/0 | F:{1} T:{} H:{2} | Book(Hotel)🔒✔ |
| 6 | LockExpired(Book(Hotel)) | Booking | F:Conf/1 T:–/0 H:–/0 | F:{1} T:{} H:{2} | Book(Hotel) |
| 7 | Fetched(Book(Hotel)) | Booking | F:Conf/1 T:–/0 H:–/0 | F:{1} T:{} H:{2} | Book(Hotel)🔒 |
| 8 | SideEffect(Book(Hotel)) | Booking | F:Conf/1 T:–/0 H:–/0 | F:{1} T:{} H:{2,3} | Book(Hotel)🔒✔ |
| 9 | LockExpired(Book(Hotel)) | Booking | F:Conf/1 T:–/0 H:–/0 | F:{1} T:{} H:{2,3} | Book(Hotel) |
| 10 | Fetched(Book(Hotel)) | Booking | F:Conf/1 T:–/0 H:–/0 | F:{1} T:{} H:{2,3} | Book(Hotel)🔒 |
| 11 | SideEffect(Book(Hotel)) | Booking | F:Conf/1 T:–/0 H:–/0 | F:{1} T:{} H:{2,3,4} | Book(Hotel)🔒✔ |
| 12 | Completed(Book(Hotel)) | Review | F:Conf/1 T:–/0 H:Conf/4 | F:{1} T:{} H:{2,3,4} | – |
| 13 | UserConfirmed | Ended | F:Conf/1 T:–/0 H:Conf/4 | F:{1} T:{} H:{2,3,4} | – |
