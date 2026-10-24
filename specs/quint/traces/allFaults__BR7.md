**allFaults / BR7_endIsAllOrNothing**  
need=F+H; cancel refused=F

| # | event | phase | process status/ref | supplier active | open tasks |
|---|---|---|---|---|---|
| 0 | Started | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight) |
| 1 | Fetched(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight)🔒 |
| 2 | HandlerFailed(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight) |
| 3 | Fetched(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight)🔒 |
| 4 | SideEffect(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Flight)🔒✔ |
| 5 | LockExpired(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Flight) |
| 6 | Fetched(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Flight)🔒 |
| 7 | HandlerFailed(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Flight) |
| 8 | Fetched(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Flight)🔒 |
| 9 | HandlerFailed(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Flight) |
| 10 | Fetched(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Flight)🔒 |
| 11 | SideEffect(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1,3} T:{} H:{} | Book(Flight)🔒✔ |
| 12 | Completed(Book(Flight)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{} | Book(Hotel) |
| 13 | Fetched(Book(Hotel)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{} | Book(Hotel)🔒 |
| 14 | SideEffect(Book(Hotel)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{5} | Book(Hotel)🔒✔ |
| 15 | LockExpired(Book(Hotel)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{5} | Book(Hotel) |
| 16 | Fetched(Book(Hotel)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{5} | Book(Hotel)🔒 |
| 17 | HandlerFailed(Book(Hotel)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{5} | Book(Hotel) |
| 18 | Fetched(Book(Hotel)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{5} | Book(Hotel)🔒 |
| 19 | SideEffect(Book(Hotel)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{5,6} | Book(Hotel)🔒✔ |
| 20 | LockExpired(Book(Hotel)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{5,6} | Book(Hotel) |
| 21 | Fetched(Book(Hotel)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{5,6} | Book(Hotel)🔒 |
| 22 | HandlerFailed(Book(Hotel)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{5,6} | Book(Hotel) |
| 23 | Fetched(Book(Hotel)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{5,6} | Book(Hotel)🔒 |
| 24 | SideEffect(Book(Hotel)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{5,6,7} | Book(Hotel)🔒✔ |
| 25 | LockExpired(Book(Hotel)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{5,6,7} | Book(Hotel) |
| 26 | Fetched(Book(Hotel)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{5,6,7} | Book(Hotel)🔒 |
| 27 | SideEffect(Book(Hotel)) | Booking | F:Conf/4 T:–/0 H:–/0 | F:{1,3} T:{} H:{5,6,7,8} | Book(Hotel)🔒✔ |
| 28 | Completed(Book(Hotel)) | Review | F:Conf/4 T:–/0 H:Conf/8 | F:{1,3} T:{} H:{5,6,7,8} | – |
| 29 | UserConfirmed | Ended | F:Conf/4 T:–/0 H:Conf/8 | F:{1,3} T:{} H:{5,6,7,8} | – |
