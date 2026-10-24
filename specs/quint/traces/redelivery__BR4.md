**redelivery / BR4_atMostOneActiveBooking**  
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
