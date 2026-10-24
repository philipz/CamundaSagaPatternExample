**allFaults / BR8_neverStuckHoldingBookings**  
need=H; cancel refused=T+H

| # | event | phase | process status/ref | supplier active | open tasks |
|---|---|---|---|---|---|
| 0 | Started | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Hotel) |
| 1 | Fetched(Book(Hotel)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Hotel)🔒 |
| 2 | SideEffect(Book(Hotel)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{1} | Book(Hotel)🔒✔ |
| 3 | Completed(Book(Hotel)) | Review | F:–/0 T:–/0 H:Conf/1 | F:{} T:{} H:{1} | – |
| 4 | UserCanceled | Compensating | F:–/0 T:–/0 H:Conf/1 | F:{} T:{} H:{1} | Cancel(Hotel) |
