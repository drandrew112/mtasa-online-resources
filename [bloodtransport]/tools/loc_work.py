from locadd import add
p = "work_bloodtransport.config."
en = {p + "name": "Blood Transport", p + "description": "Carry blood products, lab samples and urgent medicine between blood supply centers and hospitals.",
      p + "skin_lab_coat": "Lab coat", p + "skin_suit": "Suit", p + "skin_business": "Business", p + "skin_business_woman": "Business (woman)",
      p + "level_trainee": "Trainee", p + "level_courier": "Courier", p + "level_senior_courier": "Senior courier", p + "level_chief_courier": "Chief courier",
      p + "vehicle": "Blood transport ambulance"}
hu = {p + "name": "Vérszállítás", p + "description": "Vérkészítmények, laborminták és sürgős gyógyszerek szállítása a vérellátó központok és a kórházak között.",
      p + "skin_lab_coat": "Laborköpeny", p + "skin_suit": "Öltöny", p + "skin_business": "Üzleti", p + "skin_business_woman": "Üzleti (nő)",
      p + "level_trainee": "Gyakornok", p + "level_courier": "Futár", p + "level_senior_courier": "Senior futár", p + "level_chief_courier": "Főfutár",
      p + "vehicle": "Vérszállító mentőautó"}
add("work_bloodtransport", en, hu)
