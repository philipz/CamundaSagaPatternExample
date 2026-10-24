**allFaults / BR4_atMostOneActiveBooking**  
need=F+H; supplier down=T+H; cancel refused=H

| # | event | phase | process status/ref | supplier active | open tasks |
|---|---|---|---|---|---|
| 0 | Started | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight) |
| 1 | Fetched(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{} T:{} H:{} | Book(Flight)🔒 |
| 2 | SideEffect(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Flight)🔒✔ |
| 3 | LockExpired(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Flight) |
| 4 | Fetched(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Flight)🔒 |
| 5 | HandlerFailed(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Flight) |
| 6 | Fetched(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Flight)🔒 |
| 7 | HandlerFailed(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Flight) |
| 8 | Fetched(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1} T:{} H:{} | Book(Flight)🔒 |
| 9 | SideEffect(Book(Flight)) | Booking | F:–/0 T:–/0 H:–/0 | F:{1,3} T:{} H:{} | Book(Flight)🔒✔ |
