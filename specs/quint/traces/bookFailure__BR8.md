**bookFailure / BR8_neverStuckHoldingBookings**  
need=T+H; supplier down=F+H

| # | event | phase | process status/ref | supplier active | open tasks |
|---|---|---|---|---|---|
| 0 | Started | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Train) |
| 1 | Fetched(Book(Train)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Train)🔒 |
| 2 | SideEffect(Book(Train)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{1} H:{} | Book(Train)🔒✔ |
| 3 | Completed(Book(Train)) | Booking | F:–/0 T:Conf/1 H:–/0 | F:{} T:{1} H:{} | Book(Hotel) |
