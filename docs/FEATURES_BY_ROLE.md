# Funkcionalnosti po vlogah

Stanje: **v3.11** (2026-09-30)

## Vloge

Aplikacija pozna tri vloge uporabnikov. Vsaka višja vloga ima tudi vse funkcionalnosti nižjih.

| Vloga | Oznaka v sistemu | Kaj vidi |
|---|---|---|
| **Operater** | `operator` | Svoje naloge in nedodeljene naloge, samo svojo evidenco dela |
| **Vodja organizacije** | `supervisor` | Vse naloge, evidenco dela vseh operaterjev v svoji organizaciji |
| **Administrator** | `admin` | Vse — plus ustvarjanje in urejanje nalogov, strank in uporabnikov |

Poleg tega obstaja še **stranka brez računa**, ki prek povezave izpolni deklaracijo posevkov.

---

## 1. Operater

**Prijava in aplikacija**
- Prijava z e-pošto in geslom, ponastavitev pozabljenega gesla po e-pošti
- Namestitev na telefon (PWA), prikaz verzije aplikacije
- Prikaz seznamov v obliki kartic ali kompaktno

**Delovni nalogi**
- Vidi samo naloge, ki so dodeljeni njemu, ter še nedodeljene naloge
- Iskanje po stranki (s predlogi) in filter po statusu (več statusov hkrati)
- Za vsak nalog: datum vnosa, stranka, število GERK-ov, skupni ha, status
- Pregledni zemljevid nalogov — oznake ob oddaljenem pogledu, oblike parcel ob približanju; ob prehodu miške prikaže stranko in GERK, klik na GERK/segment prikaže samo tisti nalog v seznamu za odpiranje

**Podrobnosti naloga**
- Glava s stranko, datumom in statusom (samo za branje), kdo je delal na nalogu in skupni čas
- Izbira datuma (tudi za nazaj, za naknadni vnos)
- Za vsak GERK:
  - **Start** / **Konec** za beleženje časa
  - Svinčnik za popravek datuma, začetka ali konca
  - Ko kdorkoli vpiše čas, se GERK obarva zeleno in zaklene
  - Prikaz, kdo drug je delal na tem GERK-u in kdaj
- Segmenti in vzorci GERK-a (št. vzorca, vzorčenje, globina, tip LAB analize) — samo za branje
- Pisanje opomb na segmente / vzorce
- **Čas na poti** — več vnosov, vsak z vrsto vozila (traktor ipd.), trajanjem in opombo; brisanje vnosov
- Traktor (predlogi iz lastne zgodovine) in opombe — vse se shrani samodejno
- Zemljevid parcel naloga, ki ga lahko razširiš, z imenom izbranega GERK-a
- Pri nalogih **Vzorčenje** (status Plan ali V delu): zajem GPS točk na terenu (**Zajemi točko**), seznam točk, prikaz na zemljevidu, brisanje

**Evidenca dela**
- Samo lastni vnosi, po mesecih
- Seštevki: število vnosov, ure dela, ure na poti, število GERK-ov, čas na poti po vrsti vozila
- Vnosi arhiviranih nalogov so skriti

---

## 2. Vodja organizacije

Vse, kar ima Operater, in dodatno:
- Vidi **vse** delovne naloge, ne le dodeljenih / nedodeljenih
- Vidi vpisane čase in čas na poti drugih operaterjev na kateremkoli nalogu
- V Evidenci dela vidi vnose vseh operaterjev **svoje organizacije**, z imenom pri vsakem vnosu
- Značka »Nadzornik« v glavi
- Ne more ustvarjati, urejati ali brisati ničesar razen lastnih vpisov

---

## 3. Administrator

Vse zgoraj, in dodatno:

**Stikalo Admin / Uporabnik** v glavi — skrije vse skrbniške gumbe (npr. za ogled, kaj vidi operater), ne spremeni pa prikazanih podatkov.

**Delovni nalogi**
- Ustvarjanje naloga (**+ Nov delovni nalog**): stranka, izvajalec, vrsta storitve, GERK-i s ha in lokacijo, segmenti, stroški, status, opombe
- Uvoz con iz KML (več datotek hkrati, prilagojeni / razdeljeni GERK-i, predlogi GERK-ov, opozorilo ob neujemanju številke GERK-a)
- Uvoz seznama GERK-ov z lepljenjem
- Sprememba statusa (Plan → V delu → Izvedeno → Izdan račun); nalog se samodejno zaključi, ko so vsi GERK-i opravljeni
- Dodajanje GERK-a obstoječemu nalogu, odstranjevanje GERK-a, odstranjevanje segmentacije con
- Sestavljen vnos GERK-a (npr. "688697+6492082+6492080"), kadar eno dejansko polje sestavlja več uradnih GERK-ov — zemljevid prikaže in izračuna vse združene meje kot en vnos
- Dodajanje stranke nalogu, ki je (izjemoma) nima — "+ Dodaj stranko" v glavi naloga; enako kot pri ustvarjanju naloga je mogoče tudi ustvariti povsem novo stranko na mestu ("+ Dodaj novo stranko")
- Izbira več GERK-ov → **izvoz v KML** ali skupno brisanje
- Dodajanje, urejanje in brisanje segmentov / vzorcev (št. vzorca, vzorčenje, globina) ter tip LAB analize (basic / micro elements)
- Urejanje vpisanih časov kateregakoli operaterja
- Arhiviranje in obnova nalogov, skupno arhiviranje več nalogov, pregled arhiva
- Vidi vso evidenco dela, brez omejitve na organizacijo

**Planiranje** — nov zavihek, viden samo v načinu Admin
- Koledar za razporejanje odprtih delovnih nalogov: povleci nalog na dan koledarja
- Kartice odprtih nalogov: številka pred imenom stranke (razvrščeno padajoče po njej), skupno število GERK-ov, segmentov in ha (enako kot na glavnem seznamu Delovni nalogi)
- Filter po izvajalcu (celoten seznam upravičenih izvajalcev, ne le tistih z odprtim nalogom)
- Ob dvokliku na nalog: izbira, katere GERK-e vključiš v ta datum, s predogledom na zemljevidu
- Dodelitev izvajalca neposredno s kartice; barvna oznaka izvajalca na koledarju (poleg zeleno/rumeno za dokončano/delno razporejeno)

**Seznam strank**
- Seznam strank z iskanjem in podrobnosti stranke
- Ustvarjanje povezave za deklaracijo (jezik samodejno), kopiranje, pošiljanje po e-pošti / ponovno pošiljanje, zgodovina povezav
- Pregled oddanih deklaracij posevkov po parcelah
- Arhiviranje stranke (arhivira tudi njene parcele in naloge) in obnova

**Izvajalci (uporabniki)**
- Dodajanje uporabnika in pošiljanje prijavnih podatkov po e-pošti
- Ponastavitev gesla, brisanje uporabnika
- Nastavitev vloge in organizacije (Vodja organizacije mora imeti organizacijo)
- Izbira, kdo je lahko izbran kot izvajalec naloga (kljukica)

> Orodja za ustvarjanje in upravljanje (vključno s Seznamom strank in Izvajalci) so dostopna samo prek plavajočega gumba **+**, ki je viden samo v načinu Admin.

---

## Stranka (brez računa)

- Prek prejete povezave odpre `deklaracija.html` brez prijave
- Izpolni deklaracijo posevkov za svoje parcele v slovenščini ali hrvaščini
- Do izteka povezave se lahko vrne in odgovore popravi
