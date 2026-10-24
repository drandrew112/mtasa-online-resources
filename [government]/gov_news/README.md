# gov_news — government news

Part of `[government]` (see gov_core README). /gov page **News** (category Public affairs).
Table `gov_news`.

A minister writes the news in every language (at least one); it is sent as a phone mail (ui_phone
`sendPhoneMail`, kind `gov_news`) to every account, each reader in their own language. Deleting the
news takes the mails back (`deletePhoneMailGroup`). Sender name: text key `gov_news.mail.sender`.

Event: `onGovNewsPosted(newsId, texts)`.
