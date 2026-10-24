**redelivery / BR5_displayMatchesSupplier**  
need=F+T+H

| # | event | phase | process status/ref | supplier active | open tasks |
|---|---|---|---|---|---|
| 0 | Started | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight), Book(Train) |
| 1 | Fetched(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight)🔒, Book(Train) |
| 2 | Fetched(Book(Train)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight)🔒, Book(Train)🔒 |
| 3 | SideEffect(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Flight)🔒✔, Book(Train)🔒 |
| 4 | SideEffect(Book(Train)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{2} H:{} | Book(Flight)🔒✔, Book(Train)🔒✔ |
| 5 | LockExpired(Book(Train)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{2} H:{} | Book(Flight)🔒✔, Book(Train) |
| 6 | Completed(Book(Flight)) | Booking | F:Conf/1 T:–/0 H:–/0 | F:{1} T:{2} H:{} | Book(Train) |
| 7 | Fetched(Book(Train)) | Booking | F:Conf/1 T:–/0 H:–/0 | F:{1} T:{2} H:{} | Book(Train)🔒 |
| 8 | SideEffect(Book(Train)) | Booking | F:Conf/1 T:–/0 H:–/0 | F:{1} T:{2,3} H:{} | Book(Train)🔒✔ |
| 9 | LockExpired(Book(Train)) | Booking | F:Conf/1 T:–/0 H:–/0 | F:{1} T:{2,3} H:{} | Book(Train) |
| 10 | Fetched(Book(Train)) | Booking | F:Conf/1 T:–/0 H:–/0 | F:{1} T:{2,3} H:{} | Book(Train)🔒 |
| 11 | SideEffect(Book(Train)) | Booking | F:Conf/1 T:–/0 H:–/0 | F:{1} T:{2,3,4} H:{} | Book(Train)🔒✔ |
| 12 | LockExpired(Book(Train)) | Booking | F:Conf/1 T:–/0 H:–/0 | F:{1} T:{2,3,4} H:{} | Book(Train) |
| 13 | Fetched(Book(Train)) | Booking | F:Conf/1 T:–/0 H:–/0 | F:{1} T:{2,3,4} H:{} | Book(Train)🔒 |
| 14 | SideEffect(Book(Train)) | Booking | F:Conf/1 T:–/0 H:–/0 | F:{1} T:{2,3,4,5} H:{} | Book(Train)🔒✔ |
| 15 | Completed(Book(Train)) | Booking | F:Conf/1 T:Conf/5 H:–/0 | F:{1} T:{2,3,4,5} H:{} | Book(Hotel) |
| 16 | Fetched(Book(Hotel)) | Booking | F:Conf/1 T:Conf/5 H:–/0 | F:{1} T:{2,3,4,5} H:{} | Book(Hotel)🔒 |
| 17 | SideEffect(Book(Hotel)) | Booking | F:Conf/1 T:Conf/5 H:–/0 | F:{1} T:{2,3,4,5} H:{6} | Book(Hotel)🔒✔ |
| 18 | LockExpired(Book(Hotel)) | Booking | F:Conf/1 T:Conf/5 H:–/0 | F:{1} T:{2,3,4,5} H:{6} | Book(Hotel) |
| 19 | Fetched(Book(Hotel)) | Booking | F:Conf/1 T:Conf/5 H:–/0 | F:{1} T:{2,3,4,5} H:{6} | Book(Hotel)🔒 |
| 20 | SideEffect(Book(Hotel)) | Booking | F:Conf/1 T:Conf/5 H:–/0 | F:{1} T:{2,3,4,5} H:{6,7} | Book(Hotel)🔒✔ |
| 21 | Completed(Book(Hotel)) | Review | F:Conf/1 T:Conf/5 H:Conf/7 | F:{1} T:{2,3,4,5} H:{6,7} | – |
