-- ============================================================
-- WorkTracker — Deduplicate customers created by two bulk-import
-- events on 2026-04-15 and 2026-04-17 (same roster imported twice,
-- pre-dates this session — not related to the 2026-08-02 historical
-- work-order import). 112 of 121 duplicate-name groups have no
-- conflicting email and are handled here; the remaining 9 groups
-- have two different real emails under the same name and need a
-- manual call — see customer_dedup_conflicts.md.
--
-- For each group: re-point every foreign key from the duplicate
-- row(s) to the surviving row, then delete the duplicates. Wrapped
-- in a transaction — if anything fails, nothing is applied.
-- ============================================================

begin;

-- adelita knežević — keep 2e07bc4d-4793-40e0-9be3-2040189ff553, remove 1 duplicate(s)
delete from public.customers where id in ('38b5a593-efdb-4cbe-9bfd-33c18a61995b');

-- agro promina d.o.o. — keep 342d281d-a405-407a-8cf9-16b61d099d94, remove 1 duplicate(s)
delete from public.customers where id in ('e7790f25-1906-4b46-9c09-e398bc3b40ab');

-- aleš  pršina — keep ebba3e96-34e9-4cef-8fd0-5f7ced69ef76, remove 1 duplicate(s)
delete from public.customers where id in ('1a256d00-5a04-41ee-a154-3bc15fdd8073');

-- aleš plut — keep 3b579163-e499-4e58-b545-0116ce2e20f0, remove 1 duplicate(s)
delete from public.customers where id in ('d0a788da-a826-4d51-839f-7d618175a109');

-- andrej ucman — keep 3314db13-9497-41ee-934d-6b0f02ff7c6a, remove 1 duplicate(s)
delete from public.customers where id in ('71a91195-9855-4f66-9a4f-ed7b7207c5f7');

-- ante marić — keep e0c735c9-952d-45e3-ab47-b82b82ef7b47, remove 1 duplicate(s)
delete from public.customers where id in ('1fe7d2a5-6b4a-44dd-85e8-bba14017bfbb');

-- bogdan dular — keep 5550d77d-3073-43ff-ac4b-e9f51666a206, remove 1 duplicate(s)
delete from public.customers where id in ('e3167d5a-2b58-4abf-8349-f16052604f5d');

-- boštjan  furlan — keep 049f2ddb-6f07-48d7-afa9-6c23a5757684, remove 1 duplicate(s)
delete from public.customers where id in ('d8e84740-dc12-44ca-b138-6032469ed7c3');

-- božić d.o.o. — keep 0661833b-e8b1-46e5-bdb7-98e77f4d0847, remove 1 duplicate(s)
delete from public.customers where id in ('50849bc6-9fa7-4927-85f3-3d7e614d6244');

-- breda durcik — keep 01b54c77-856d-4413-8e0c-e016e40dad54, remove 1 duplicate(s)
delete from public.customers where id in ('3894bf1f-bfd0-48e8-ac8a-d357160fda1c');

-- čedomir pavlović — keep c9046815-8c50-4c08-a8ed-11dd2a4bb971, remove 1 duplicate(s)
delete from public.customers where id in ('4d8041b0-e7c7-46b6-9b55-d3210181c8e9');

-- dalibor dundović — keep 220ec98e-af91-493f-bf2b-94576927c943, remove 1 duplicate(s)
delete from public.customers where id in ('ff0ca228-c0c8-4a8e-9d9e-e6198723f817');

-- damjan novak — keep 8cd6bb95-d497-4617-947e-6d223b7aba0e, remove 1 duplicate(s)
delete from public.customers where id in ('f9ed97af-8edd-4c59-bb4a-03d58b6571d1');

-- damljan štoklej — keep b8601503-f677-4c81-a2b8-8aee8fa1a5d6, remove 1 duplicate(s)
delete from public.customers where id in ('f076c560-c3ce-48a7-959e-205a4d4f0e12');

-- daniel lukač — keep b7ff2a39-0a2e-49f0-aea4-e707b2504c95, remove 1 duplicate(s)
delete from public.customers where id in ('a05810ef-a2c6-4978-864b-5d7300f4b741');

-- darko  kovačević — keep 99049d39-930c-4048-8dfa-379991e9976e, remove 1 duplicate(s)
delete from public.customers where id in ('b5cd7923-2079-4ea4-95b6-00a03fa16053');

-- dean kokot — keep 8cf8ea6b-b392-4ab8-b63a-8792397e598b, remove 1 duplicate(s)
delete from public.customers where id in ('75daaad0-6787-4f78-9853-ebbaf383fe41');

-- djuradj  cvijić — keep 5beb9cda-903c-4e1c-8bc8-312d12bf0c89, remove 1 duplicate(s)
delete from public.customers where id in ('31a8d3e2-776d-4fa4-8dc3-8f1b49942f35');

-- dominik  vrtič — keep 0201dad6-b5f4-419c-89c8-080e3fee2e33, remove 1 duplicate(s)
delete from public.customers where id in ('ac093b1e-5733-47b6-bef8-70776a6fe536');

-- drago sinur — keep 43e738cd-a810-4238-8168-7a673f4ea210, remove 3 duplicate(s)
delete from public.fields where id = '192ff0c6-8517-4c6d-8ad3-09245b63970d'; -- duplicate of 58cb2e85-bca9-4f20-a1a3-631702c2232b, MAROF (1284417)
delete from public.fields where id = 'eab461f6-9951-4560-aa6c-b05585b342ad'; -- duplicate of 800cd681-6ba8-44d4-a59d-ffe3bf0ceb16, NA HRIBU (1284739)
delete from public.fields where id = 'dd0524fb-a8e5-43d4-8ca8-3d3744e00d6d'; -- duplicate of 90abe864-20cc-4f72-8352-413cff75c784, POD BRINOVCEM (1284741)
delete from public.fields where id = 'de167f68-afb3-40a0-8b11-ec344b333ac0'; -- duplicate of 7e09ef1d-975d-4fcd-85a1-85e9094a6c7d, IRENGA (1284750)
delete from public.fields where id = '2d42e219-ef25-445a-8924-eae326144d24'; -- duplicate of ac0fc337-b5f0-413e-a01f-25ba77c5fe6d, DEU 5 - NOVAKOVKA (1318762)
delete from public.fields where id = '4ff1dd38-5b49-4444-92d0-414712263468'; -- duplicate of c31818be-5d1f-4ae6-9ae9-67f6565f8d04, DEU 6 - LOČICE (1318764)
delete from public.fields where id = '5736f13c-cc5f-4e27-b082-8a4349c566d0'; -- duplicate of 9e5eda75-8bd0-400e-a8da-3e718610d0cb, NA PLAZU (1318769)
delete from public.fields where id = '1192103a-7ebb-439b-960d-cbc28103e09f'; -- duplicate of 0b7108e4-fa08-43d4-a18d-08762a12d01c, MRČN DOL (1826237)
delete from public.fields where id = 'becae20d-9c59-4bb2-95e8-a2c4e7c3ca34'; -- duplicate of b99e3a43-c343-4ae5-926e-99365f7f7654, DREVESNICA (1835748)
delete from public.fields where id = 'b4f1d5d0-90f5-4130-b944-9def77bc6aac'; -- duplicate of f7a4c302-3ea5-474d-b050-2140e29c9278, DREVESNICA 1 (3411871)
delete from public.fields where id = '0f4e02c3-cd9e-4b34-b6c6-d2a196ad93a4'; -- duplicate of c26b767f-78a2-4b0d-8f0e-f57bb01493c7, ŠTANGREB (3411666)
delete from public.fields where id = '3a623ab3-f911-4e7e-9dd6-131176cd9422'; -- duplicate of bfa60b62-9fac-4cd4-ad3c-4fbdbe914335, DEU - PRI ŽAGI (3412996)
delete from public.fields where id = '1017af42-89b0-44a1-a3c9-1d85b7667bc4'; -- duplicate of 059c0d47-0b02-4862-86bd-ab99b8c5967f, PRI ŽGAJNARJU (4380773)
delete from public.fields where id = '2175270c-3bde-479d-a13a-aca715e051e2'; -- duplicate of de76d13e-42a7-46c1-aa1c-5d2f23873387, ŠTANGREB (3411666-1)
delete from public.fields where id = '8142b1f5-bf60-4ead-8d26-a4515e9e6901'; -- duplicate of 330dcfcb-06ed-4153-9dba-4bb05c34bc91, ŠTANGREB (3411666-2)
update public.delovni_nalogi set stranka_id = '43e738cd-a810-4238-8168-7a673f4ea210' where stranka_id in ('4ffb9e0d-3c2b-40d2-9e14-eb3cc77cb2c5', 'e061b790-c101-402d-a360-c56d94a03e8e', '024c3b8a-738e-4685-a036-432bc15b7053');
update public.field_declarations set customer_id = '43e738cd-a810-4238-8168-7a673f4ea210' where customer_id in ('4ffb9e0d-3c2b-40d2-9e14-eb3cc77cb2c5', 'e061b790-c101-402d-a360-c56d94a03e8e', '024c3b8a-738e-4685-a036-432bc15b7053');
update public.customer_links set customer_id = '43e738cd-a810-4238-8168-7a673f4ea210' where customer_id in ('4ffb9e0d-3c2b-40d2-9e14-eb3cc77cb2c5', 'e061b790-c101-402d-a360-c56d94a03e8e', '024c3b8a-738e-4685-a036-432bc15b7053');
update public.orders set customer_id = '43e738cd-a810-4238-8168-7a673f4ea210' where customer_id in ('4ffb9e0d-3c2b-40d2-9e14-eb3cc77cb2c5', 'e061b790-c101-402d-a360-c56d94a03e8e', '024c3b8a-738e-4685-a036-432bc15b7053');
update public.reports set customer_id = '43e738cd-a810-4238-8168-7a673f4ea210' where customer_id in ('4ffb9e0d-3c2b-40d2-9e14-eb3cc77cb2c5', 'e061b790-c101-402d-a360-c56d94a03e8e', '024c3b8a-738e-4685-a036-432bc15b7053');
delete from public.customers where id in ('4ffb9e0d-3c2b-40d2-9e14-eb3cc77cb2c5', 'e061b790-c101-402d-a360-c56d94a03e8e', '024c3b8a-738e-4685-a036-432bc15b7053');

-- ego vina d.o.o. — keep 22af02d7-c6d4-4629-804a-092f82013acb, remove 1 duplicate(s)
delete from public.customers where id in ('4a0a5e36-81d9-43cb-92a6-78477cfcc0c9');

-- emil vidovič — keep 85991dc5-5abc-41ad-9c86-6bf7e2630ce9, remove 1 duplicate(s)
delete from public.customers where id in ('d150e768-412a-4c00-9a3b-ce61e9a215d8');

-- evrosad d.o.o. — keep 5dea4a32-2559-4d0a-995a-f50062f5463b, remove 1 duplicate(s)
delete from public.customers where id in ('ca494130-e3b4-48d0-80b6-0bb4642d463c');

-- franc bartelj — keep afc67237-ec7e-43ce-aea4-bd9d7c6b682f, remove 1 duplicate(s)
delete from public.customers where id in ('86d61a38-d0ed-46d0-b2b2-46e4b0d9f87b');

-- franc hrastar — keep c8851b42-e421-464d-bf41-a6ffbfa86652, remove 1 duplicate(s)
delete from public.customers where id in ('42789e1e-ff4d-4672-a824-b6ac8fc967ae');

-- franci fon — keep e3847246-ebfb-4f8f-8be9-b996709639cb, remove 1 duplicate(s)
delete from public.customers where id in ('79dd6e36-a4b1-4d34-ac73-32ebda881e92');

-- goran  mitrović — keep a5226a99-7dd4-43ca-99b9-baf33ff081fb, remove 1 duplicate(s)
delete from public.customers where id in ('3765167d-04dd-413a-9018-9c3e4c772515');

-- granum d.o.o. — keep 2403e57e-5958-42a4-ae32-2575c72f23c8, remove 1 duplicate(s)
delete from public.customers where id in ('8777b399-7d02-4d74-adb2-14fc85afa7be');

-- gregor štemberger — keep bb0a960c-eb48-4f42-bb26-c916887af390, remove 1 duplicate(s)
delete from public.customers where id in ('7c7ae105-cfee-4230-bc94-f8c44b08cbba');

-- hpg d.o.o. — keep a69c01f4-2ea0-4a56-bddd-c29394d98fe8, remove 1 duplicate(s)
delete from public.customers where id in ('10cabad8-ee62-41fd-b593-7116be1d2ac7');

-- hrvoje  brkanić — keep e555670e-e950-45d4-831b-29a1c2a3801b, remove 1 duplicate(s)
delete from public.customers where id in ('f7c4c3d7-7760-43a2-9899-61bd3e26d296');

-- igor maršić — keep fa799ba4-0598-4b1a-8e7f-0d5f1ab01b53, remove 1 duplicate(s)
delete from public.customers where id in ('d13186bb-963b-492a-9797-68227d7ac071');

-- ilija kordič — keep 31eee9f8-a2e2-440d-ab2a-bb1308d9b682, remove 1 duplicate(s)
delete from public.customers where id in ('af3af13b-6328-45f5-9233-03be4d32adcf');

-- iločki podrumi — keep 8b1dddbb-bc53-4668-a410-e05dc354a2dc, remove 1 duplicate(s)
delete from public.customers where id in ('cb4c8a46-8055-4c4b-9bf5-e5afdfde6e06');

-- ivan jozinović — keep 4d325e27-d034-42be-b23d-6115ad27aadf, remove 1 duplicate(s)
delete from public.customers where id in ('eb0cc313-81d2-489d-9525-2d18e6508bae');

-- ivan marić — keep 32a5b8ae-2c5e-406e-baab-ef5e49cbce74, remove 1 duplicate(s)
delete from public.customers where id in ('b2403e92-445a-4509-b415-15f5f6dbd098');

-- janec colnar — keep 0627e08c-61b0-4383-8e6b-6f88b96b2e75, remove 1 duplicate(s)
delete from public.customers where id in ('497ce3cc-3c14-4c8d-9a9e-640c21e3db6d');

-- janez šebat — keep ba8cd5a5-fb56-44a2-af4a-bd9d8ca6b04b, remove 1 duplicate(s)
delete from public.customers where id in ('c39e3367-3ad5-4558-bc5b-2560919f2b69');

-- janez šekoranja — keep 00f777c7-4b55-4008-940b-71b47e7bf258, remove 1 duplicate(s)
delete from public.customers where id in ('d06eb878-e853-4e0c-8fb9-48ef1ff33bef');

-- janko petrovič — keep d82515c2-8551-46db-ad20-7a5d85da8839, remove 1 duplicate(s)
delete from public.customers where id in ('603f1251-6686-4145-9533-e2e0829a4732');

-- jelena babić — keep f2b864c3-703a-4711-9a5c-e32b15f67550, remove 1 duplicate(s)
delete from public.customers where id in ('3e92c40c-88d2-4f4b-a032-36ac4f3e99fd');

-- jernej kostrevc — keep 62edc16b-fccc-42dc-9780-858fec885dfe, remove 1 duplicate(s)
delete from public.customers where id in ('fcb1a339-6940-4a58-b28a-a6eb298c9f9d');

-- josip brkanić — keep 1b22443f-0a7e-4e70-ba60-b18238f82f04, remove 1 duplicate(s)
delete from public.customers where id in ('f3d7f766-2c0c-4e26-a233-5b1b954747e5');

-- josip koški — keep cd55425f-6129-4a23-81c0-80f677480768, remove 3 duplicate(s)
delete from public.fields where id = '32171325-069a-4663-bc86-c340c20db74d'; -- duplicate of 263657d1-431c-4a9a-904f-5da0fc249d4e, GORIČANI PAPRIKAR (2548011)
delete from public.fields where id = '9f727511-7199-4ed8-9286-5a84109946bb'; -- duplicate of 83ee96c7-a58f-4927-b165-a58f3500a3ee, KOD SALAŠA (2317384)
update public.delovni_nalogi set stranka_id = 'cd55425f-6129-4a23-81c0-80f677480768' where stranka_id in ('499fe347-1730-4afb-9f98-2f859602992d', 'e09e7572-e595-4f4d-9871-f96a9b5e3b6b', 'f2cb30a5-3074-4f87-a2bb-a0c56b66f2d4');
update public.field_declarations set customer_id = 'cd55425f-6129-4a23-81c0-80f677480768' where customer_id in ('499fe347-1730-4afb-9f98-2f859602992d', 'e09e7572-e595-4f4d-9871-f96a9b5e3b6b', 'f2cb30a5-3074-4f87-a2bb-a0c56b66f2d4');
update public.customer_links set customer_id = 'cd55425f-6129-4a23-81c0-80f677480768' where customer_id in ('499fe347-1730-4afb-9f98-2f859602992d', 'e09e7572-e595-4f4d-9871-f96a9b5e3b6b', 'f2cb30a5-3074-4f87-a2bb-a0c56b66f2d4');
update public.orders set customer_id = 'cd55425f-6129-4a23-81c0-80f677480768' where customer_id in ('499fe347-1730-4afb-9f98-2f859602992d', 'e09e7572-e595-4f4d-9871-f96a9b5e3b6b', 'f2cb30a5-3074-4f87-a2bb-a0c56b66f2d4');
update public.reports set customer_id = 'cd55425f-6129-4a23-81c0-80f677480768' where customer_id in ('499fe347-1730-4afb-9f98-2f859602992d', 'e09e7572-e595-4f4d-9871-f96a9b5e3b6b', 'f2cb30a5-3074-4f87-a2bb-a0c56b66f2d4');
delete from public.customers where id in ('499fe347-1730-4afb-9f98-2f859602992d', 'e09e7572-e595-4f4d-9871-f96a9b5e3b6b', 'f2cb30a5-3074-4f87-a2bb-a0c56b66f2d4');

-- josip šoštarić — keep 6d7f3030-3711-4cb6-9d6e-145167df52da, remove 1 duplicate(s)
delete from public.customers where id in ('172582a8-f8f2-431e-9bde-e8eb509b9b36');

-- jože šarc — keep 65d0de89-72f6-4dd9-85ba-bbe8b507823a, remove 1 duplicate(s)
delete from public.customers where id in ('5f6526c9-1617-42d6-a7a6-0e1f716462a8');

-- jožef čas — keep 07cb34f1-aedd-4fa0-8bf1-def41b7eaa85, remove 1 duplicate(s)
delete from public.customers where id in ('90010219-990f-4e30-b330-96330e307fb5');

-- junc roman — keep 8d15f47c-b5dd-4a04-833f-a3252f72b33f, remove 1 duplicate(s)
delete from public.customers where id in ('dd168061-6388-4d52-bc0c-796a65935f89');

-- kabaj — keep e485c55c-5a6a-4fad-9c30-c4070eb83372, remove 1 duplicate(s)
delete from public.customers where id in ('94270a0d-624b-4000-bb83-7abbb8e43da1');

-- kartuzija pleterje d.o.o. — keep 8d7a00c3-e478-4777-84df-7d9306d19023, remove 1 duplicate(s)
delete from public.customers where id in ('ba8b5f30-a48a-4b72-a729-0bab6d3a0f0a');

-- klavdij furlan — keep 55127a1f-d313-406a-a718-437f1aeb7746, remove 1 duplicate(s)
delete from public.customers where id in ('4e0d9547-3c75-44d2-9f0d-709e767d85c5');

-- kmetija faktor — keep 78dbd9a5-76f6-427d-8ce5-80788ed81da3, remove 1 duplicate(s)
delete from public.customers where id in ('b33a2f8b-14ac-4864-ba67-a7b12d04b668');

-- kutjevo d.d. kutjevo d.d. — keep 1f2b17e5-5aa6-4301-a47b-73f1070faaef, remove 1 duplicate(s)
delete from public.customers where id in ('ed2d41bf-ee70-4d0c-8395-9b80c08fef1a');

-- lado mandac — keep 54847950-b0e4-44c3-809b-4c2c79a5524a, remove 1 duplicate(s)
delete from public.customers where id in ('7059d512-457e-401f-8053-404af39167f4');

-- leopold miš — keep 776c7ef0-15e3-416c-86f7-cee7325b1319, remove 1 duplicate(s)
delete from public.customers where id in ('67621784-ebb9-4c0a-b707-97d7a3e1e4c4');

-- ljubiša dukić — keep 72d5e0b7-0b11-4d6d-8bf6-4426e1c48409, remove 2 duplicate(s)
update public.fields set customer_id = '72d5e0b7-0b11-4d6d-8bf6-4426e1c48409' where id = '594747ed-22ce-4dee-a35e-545418228b4f'; -- Rogolji (Rogolji)
update public.delovni_nalogi set stranka_id = '72d5e0b7-0b11-4d6d-8bf6-4426e1c48409' where stranka_id in ('d7a85f0c-7feb-4974-80ea-4e4c495735d9', '36f65b0d-395b-4650-a64c-6260ab345394');
update public.field_declarations set customer_id = '72d5e0b7-0b11-4d6d-8bf6-4426e1c48409' where customer_id in ('d7a85f0c-7feb-4974-80ea-4e4c495735d9', '36f65b0d-395b-4650-a64c-6260ab345394');
update public.customer_links set customer_id = '72d5e0b7-0b11-4d6d-8bf6-4426e1c48409' where customer_id in ('d7a85f0c-7feb-4974-80ea-4e4c495735d9', '36f65b0d-395b-4650-a64c-6260ab345394');
update public.orders set customer_id = '72d5e0b7-0b11-4d6d-8bf6-4426e1c48409' where customer_id in ('d7a85f0c-7feb-4974-80ea-4e4c495735d9', '36f65b0d-395b-4650-a64c-6260ab345394');
update public.reports set customer_id = '72d5e0b7-0b11-4d6d-8bf6-4426e1c48409' where customer_id in ('d7a85f0c-7feb-4974-80ea-4e4c495735d9', '36f65b0d-395b-4650-a64c-6260ab345394');
delete from public.customers where id in ('d7a85f0c-7feb-4974-80ea-4e4c495735d9', '36f65b0d-395b-4650-a64c-6260ab345394');

-- luka krč — keep 87f72b48-9511-4694-b470-a167c19bface, remove 4 duplicate(s)
update public.fields set customer_id = '87f72b48-9511-4694-b470-a167c19bface' where id = '982c97ca-19a2-4914-b213-583d5be23d5e'; -- DR D7 (6123910)
delete from public.fields where id = '6751b1fc-1fa5-4de5-b8cd-e88842d46f46'; -- duplicate of 982c97ca-19a2-4914-b213-583d5be23d5e, DR D7 (6123910)
update public.delovni_nalogi set stranka_id = '87f72b48-9511-4694-b470-a167c19bface' where stranka_id in ('3b777dfe-23c9-482c-b045-1c1a481f0cc0', '2f15f3f0-f1c5-4c3a-862f-3836a394bda7', '03eb450e-66a7-4d28-a93e-89bf0268584b', 'da4d9e5f-2a19-4932-aee2-412d83b0315c');
update public.field_declarations set customer_id = '87f72b48-9511-4694-b470-a167c19bface' where customer_id in ('3b777dfe-23c9-482c-b045-1c1a481f0cc0', '2f15f3f0-f1c5-4c3a-862f-3836a394bda7', '03eb450e-66a7-4d28-a93e-89bf0268584b', 'da4d9e5f-2a19-4932-aee2-412d83b0315c');
update public.customer_links set customer_id = '87f72b48-9511-4694-b470-a167c19bface' where customer_id in ('3b777dfe-23c9-482c-b045-1c1a481f0cc0', '2f15f3f0-f1c5-4c3a-862f-3836a394bda7', '03eb450e-66a7-4d28-a93e-89bf0268584b', 'da4d9e5f-2a19-4932-aee2-412d83b0315c');
update public.orders set customer_id = '87f72b48-9511-4694-b470-a167c19bface' where customer_id in ('3b777dfe-23c9-482c-b045-1c1a481f0cc0', '2f15f3f0-f1c5-4c3a-862f-3836a394bda7', '03eb450e-66a7-4d28-a93e-89bf0268584b', 'da4d9e5f-2a19-4932-aee2-412d83b0315c');
update public.reports set customer_id = '87f72b48-9511-4694-b470-a167c19bface' where customer_id in ('3b777dfe-23c9-482c-b045-1c1a481f0cc0', '2f15f3f0-f1c5-4c3a-862f-3836a394bda7', '03eb450e-66a7-4d28-a93e-89bf0268584b', 'da4d9e5f-2a19-4932-aee2-412d83b0315c');
delete from public.customers where id in ('3b777dfe-23c9-482c-b045-1c1a481f0cc0', '2f15f3f0-f1c5-4c3a-862f-3836a394bda7', '03eb450e-66a7-4d28-a93e-89bf0268584b', 'da4d9e5f-2a19-4932-aee2-412d83b0315c');

-- mario žibrin — keep b24b9871-c7d0-441c-b7e9-cb1bef66ebd6, remove 1 duplicate(s)
delete from public.customers where id in ('2e133e7c-5963-4330-be5f-e718e9c338b5');

-- marjan vrhovec — keep 6165e054-91da-46bd-8182-6fcbf36958d1, remove 1 duplicate(s)
delete from public.customers where id in ('5d4e8c53-882f-4ca0-86c0-75d6e77f5496');

-- marko benčina — keep 91a810a0-d742-4601-bba7-aa4f3eb515e2, remove 1 duplicate(s)
delete from public.customers where id in ('153e8bdd-dae9-486f-9571-0a510e53087f');

-- marko hladika — keep b95aad39-ed89-48f7-9e59-48c3d822f325, remove 1 duplicate(s)
delete from public.customers where id in ('d71a6e15-4c73-48ef-a2c6-e2330c982e85');

-- marko kern — keep 0ac5a85b-aa9f-472f-bf4f-4ab460b3baca, remove 1 duplicate(s)
delete from public.customers where id in ('24ef26c2-87c4-4cab-b8ef-863edc5de415');

-- marko sladić — keep 3fa85d64-b73f-422c-a2fd-b7e66699243b, remove 1 duplicate(s)
delete from public.customers where id in ('938e15f2-f092-40cc-bc54-b3764c8510a0');

-- marko slak — keep 600eebb6-0769-45d0-999a-685a66e1d458, remove 1 duplicate(s)
delete from public.customers where id in ('e415fbb4-a7c8-45f4-a45f-eefe8165734f');

-- martin  pečarič — keep c4149da5-de0b-48ca-90cf-f0458fc987d6, remove 1 duplicate(s)
delete from public.customers where id in ('f73efac5-bc59-4bc2-b088-b575e7c656f3');

-- matej resnik — keep 54f74c14-68b6-42fd-a31a-b8d7cd3f0311, remove 1 duplicate(s)
delete from public.customers where id in ('ceac5fe9-bb1b-4719-bed3-3cfb6963a900');

-- matjaž koren — keep 87c24282-55d5-40b1-bfa0-b1220835a419, remove 1 duplicate(s)
delete from public.customers where id in ('cd6b99f5-ef36-44fb-9267-d94220dc92ec');

-- miha štokar — keep 24249d62-96f5-40d6-a32f-13305ae6f197, remove 1 duplicate(s)
delete from public.customers where id in ('33461e9e-86ce-410f-94c6-b83cdbadee83');

-- mihael sklizović — keep 660aa379-82ae-4fd3-85cf-979a897856d7, remove 4 duplicate(s)
update public.fields set customer_id = '660aa379-82ae-4fd3-85cf-979a897856d7' where id = 'ebb9d2b7-2f45-4c0c-aa4f-35a7a2755705'; -- POREC (2262916)
delete from public.fields where id = 'e93cfcd7-2943-4479-8a1d-681f381e3f90'; -- duplicate of ebb9d2b7-2f45-4c0c-aa4f-35a7a2755705, POREC (2262916)
update public.delovni_nalogi set stranka_id = '660aa379-82ae-4fd3-85cf-979a897856d7' where stranka_id in ('520c32fc-5429-49e6-b6aa-9742ff2cda68', '004b8584-491a-4b8a-a46c-2617312ca52f', 'f88b966b-edc9-4b5b-ad49-e52885bbb9bb', 'e2898682-37be-4bf8-9abc-49d8350262eb');
update public.field_declarations set customer_id = '660aa379-82ae-4fd3-85cf-979a897856d7' where customer_id in ('520c32fc-5429-49e6-b6aa-9742ff2cda68', '004b8584-491a-4b8a-a46c-2617312ca52f', 'f88b966b-edc9-4b5b-ad49-e52885bbb9bb', 'e2898682-37be-4bf8-9abc-49d8350262eb');
update public.customer_links set customer_id = '660aa379-82ae-4fd3-85cf-979a897856d7' where customer_id in ('520c32fc-5429-49e6-b6aa-9742ff2cda68', '004b8584-491a-4b8a-a46c-2617312ca52f', 'f88b966b-edc9-4b5b-ad49-e52885bbb9bb', 'e2898682-37be-4bf8-9abc-49d8350262eb');
update public.orders set customer_id = '660aa379-82ae-4fd3-85cf-979a897856d7' where customer_id in ('520c32fc-5429-49e6-b6aa-9742ff2cda68', '004b8584-491a-4b8a-a46c-2617312ca52f', 'f88b966b-edc9-4b5b-ad49-e52885bbb9bb', 'e2898682-37be-4bf8-9abc-49d8350262eb');
update public.reports set customer_id = '660aa379-82ae-4fd3-85cf-979a897856d7' where customer_id in ('520c32fc-5429-49e6-b6aa-9742ff2cda68', '004b8584-491a-4b8a-a46c-2617312ca52f', 'f88b966b-edc9-4b5b-ad49-e52885bbb9bb', 'e2898682-37be-4bf8-9abc-49d8350262eb');
delete from public.customers where id in ('520c32fc-5429-49e6-b6aa-9742ff2cda68', '004b8584-491a-4b8a-a46c-2617312ca52f', 'f88b966b-edc9-4b5b-ad49-e52885bbb9bb', 'e2898682-37be-4bf8-9abc-49d8350262eb');

-- mile soldo — keep ca58d27d-02f6-4c3c-9ab9-e6243d206d72, remove 1 duplicate(s)
delete from public.customers where id in ('c08efead-316d-45b2-97b5-fe0f0196fd75');

-- miljenko bura — keep eafee760-a804-44a0-b385-a794c05891ae, remove 1 duplicate(s)
delete from public.customers where id in ('866254bd-c99c-4f5e-a54e-e4651ab93a8d');

-- miran grubič — keep c087223a-ecf1-443d-9719-7542800fd9df, remove 1 duplicate(s)
delete from public.customers where id in ('a8447a8b-c97d-459b-ab15-1a877e721b35');

-- mitja gazvoda — keep 99ee7466-5ad7-427d-8b49-f1dda5a27425, remove 1 duplicate(s)
delete from public.customers where id in ('fb579269-e4bc-4cab-859c-30e6bc2d341f');

-- nejc dolenc — keep 0f44a341-9cb5-4ca7-aca1-060a7247b601, remove 1 duplicate(s)
delete from public.customers where id in ('be5ddc4c-64be-4125-b818-27d3836d0b60');

-- novak — keep 2b6d05fc-5b8c-4b98-b32a-857c15e7ea74, remove 3 duplicate(s)
delete from public.fields where id = '74b85e01-a212-472d-a4cc-552e9a0f6754'; -- duplicate of cfafea86-1b6e-4d17-8a5a-9cd3bd370cd0, BREZOVCE (2099284)
delete from public.fields where id = '4762340f-d64b-4cd1-8a1c-2605a287080f'; -- duplicate of baae98fd-7c26-4f55-9b19-be8a53a1d7aa, DREJNOVEC (2107780)
delete from public.fields where id = 'd2e2b1ce-0a41-4572-9c71-44ea7f40927c'; -- duplicate of ae1d3f05-ef8e-406c-a47a-4e900501f1f9, DOBJE (2107774)
update public.delovni_nalogi set stranka_id = '2b6d05fc-5b8c-4b98-b32a-857c15e7ea74' where stranka_id in ('5f280ac3-933f-4a63-9e64-3e587f6b0a90', '2209d832-836a-4e61-99c6-dcb6852f48f7', 'c5b69f2b-2c05-4037-a95a-482fcb657632');
update public.field_declarations set customer_id = '2b6d05fc-5b8c-4b98-b32a-857c15e7ea74' where customer_id in ('5f280ac3-933f-4a63-9e64-3e587f6b0a90', '2209d832-836a-4e61-99c6-dcb6852f48f7', 'c5b69f2b-2c05-4037-a95a-482fcb657632');
update public.customer_links set customer_id = '2b6d05fc-5b8c-4b98-b32a-857c15e7ea74' where customer_id in ('5f280ac3-933f-4a63-9e64-3e587f6b0a90', '2209d832-836a-4e61-99c6-dcb6852f48f7', 'c5b69f2b-2c05-4037-a95a-482fcb657632');
update public.orders set customer_id = '2b6d05fc-5b8c-4b98-b32a-857c15e7ea74' where customer_id in ('5f280ac3-933f-4a63-9e64-3e587f6b0a90', '2209d832-836a-4e61-99c6-dcb6852f48f7', 'c5b69f2b-2c05-4037-a95a-482fcb657632');
update public.reports set customer_id = '2b6d05fc-5b8c-4b98-b32a-857c15e7ea74' where customer_id in ('5f280ac3-933f-4a63-9e64-3e587f6b0a90', '2209d832-836a-4e61-99c6-dcb6852f48f7', 'c5b69f2b-2c05-4037-a95a-482fcb657632');
delete from public.customers where id in ('5f280ac3-933f-4a63-9e64-3e587f6b0a90', '2209d832-836a-4e61-99c6-dcb6852f48f7', 'c5b69f2b-2c05-4037-a95a-482fcb657632');

-- olga cvenkel — keep 36950ff4-5d54-4d9a-80ec-431c980c33ee, remove 1 duplicate(s)
delete from public.customers where id in ('34d17361-cf07-43bc-97b3-2f8e55228235');

-- oliver turkalj — keep c6a80013-79ba-4f73-832d-67f50c921995, remove 1 duplicate(s)
delete from public.customers where id in ('596f7b12-8be7-4c76-a190-ffeae2209825');

-- pavlo žorž — keep 981c00da-7bc4-4f0b-8ece-71f0c04ebb71, remove 1 duplicate(s)
delete from public.customers where id in ('32989bc5-4786-44e7-8b5c-2785ca96e2de');

-- pero marošević — keep 6e221647-de24-401e-9b37-4449bec62815, remove 1 duplicate(s)
delete from public.customers where id in ('9a07f665-74bc-4b89-a7ef-f651fbfe73eb');

-- petar cota — keep c1e2bd62-95b0-4109-95ef-bfda8232bc22, remove 1 duplicate(s)
delete from public.customers where id in ('0a4c0230-73c3-4dbf-826a-c3cbccf8d3c0');

-- petar đurić — keep 30208d70-ab01-4e61-8921-423bce45b7a3, remove 1 duplicate(s)
delete from public.customers where id in ('474684c3-8a60-4bfd-8148-80d6dc79bee4');

-- petar kocijan — keep 026bd19a-d36e-44b2-a918-22b597190117, remove 1 duplicate(s)
delete from public.customers where id in ('4356cbb2-96f0-4686-b889-817bd63e334c');

-- peter burger — keep a15b2043-32f9-4641-a854-8234fc1220a0, remove 1 duplicate(s)
delete from public.customers where id in ('d5177384-7612-4d6c-a117-7e6206ec0f22');

-- primož pevec — keep 1601a4c9-217e-4cef-ae6b-fab0a0d8fd8b, remove 1 duplicate(s)
delete from public.customers where id in ('84741ec0-f598-4c0f-90d1-e6eff34e2115');

-- radomir  damjanović — keep 66cf16d0-ffdb-4518-9ab3-aa6efc8e0f21, remove 1 duplicate(s)
delete from public.customers where id in ('25c58a94-1cd6-4542-9516-2d7503c7c09f');

-- robert bonin — keep 1209b26f-4cc0-4f85-8ea8-72e24f4bfaea, remove 3 duplicate(s)
delete from public.fields where id = 'ec286b96-8f35-4065-a80d-e277b1009676'; -- duplicate of 4242b96b-d14e-4326-a905-9f72c18ddf56, Sečovlje Bivlje (4454011)
delete from public.fields where id = '4da008ec-2f11-4bf4-bb00-bdaed70a6c1d'; -- duplicate of 0f1160d3-cbfe-46d8-b69b-72a13c4711f5, Sečovlje Bivlje 2 (3145543)
update public.delovni_nalogi set stranka_id = '1209b26f-4cc0-4f85-8ea8-72e24f4bfaea' where stranka_id in ('3b6a6ef1-4f9d-4d68-866c-477073bdf77c', '82b000ed-356a-4ceb-84ef-8bab22e25734', 'b37e9f2f-8565-4417-a947-c801ac119bee');
update public.field_declarations set customer_id = '1209b26f-4cc0-4f85-8ea8-72e24f4bfaea' where customer_id in ('3b6a6ef1-4f9d-4d68-866c-477073bdf77c', '82b000ed-356a-4ceb-84ef-8bab22e25734', 'b37e9f2f-8565-4417-a947-c801ac119bee');
update public.customer_links set customer_id = '1209b26f-4cc0-4f85-8ea8-72e24f4bfaea' where customer_id in ('3b6a6ef1-4f9d-4d68-866c-477073bdf77c', '82b000ed-356a-4ceb-84ef-8bab22e25734', 'b37e9f2f-8565-4417-a947-c801ac119bee');
update public.orders set customer_id = '1209b26f-4cc0-4f85-8ea8-72e24f4bfaea' where customer_id in ('3b6a6ef1-4f9d-4d68-866c-477073bdf77c', '82b000ed-356a-4ceb-84ef-8bab22e25734', 'b37e9f2f-8565-4417-a947-c801ac119bee');
update public.reports set customer_id = '1209b26f-4cc0-4f85-8ea8-72e24f4bfaea' where customer_id in ('3b6a6ef1-4f9d-4d68-866c-477073bdf77c', '82b000ed-356a-4ceb-84ef-8bab22e25734', 'b37e9f2f-8565-4417-a947-c801ac119bee');
delete from public.customers where id in ('3b6a6ef1-4f9d-4d68-866c-477073bdf77c', '82b000ed-356a-4ceb-84ef-8bab22e25734', 'b37e9f2f-8565-4417-a947-c801ac119bee');

-- robert kac — keep 618f278a-4ee0-4d53-ac0f-3bca42b55f9d, remove 1 duplicate(s)
delete from public.customers where id in ('304917cf-af20-4bad-906a-7aac1a7a7939');

-- sadjarstvo ormož d.o.o. — keep b09e119d-6ccf-4f59-a84f-a0add98b7898, remove 1 duplicate(s)
delete from public.customers where id in ('99dfa126-bf89-4298-bc32-45a8ef8f61a8');

-- ščurek — keep 17caa78f-ae30-409d-a1dc-cc31696f5e39, remove 1 duplicate(s)
delete from public.customers where id in ('5db7fbd5-b3fa-4bb5-8fa3-294790afcd7a');

-- simon pribac — keep 8a9cb6c1-bb1a-44cf-b37b-651f96072994, remove 1 duplicate(s)
delete from public.customers where id in ('42a8849d-e915-4777-b657-1fde772217f2');

-- slave  holetić — keep 7f934c21-5ea0-448a-af1b-1862d9060d2c, remove 1 duplicate(s)
delete from public.customers where id in ('81763c4f-0929-4604-8a63-b82b5adc446b');

-- smiljan  reljić — keep 7e6368d3-27af-4567-9beb-b3415d48c852, remove 1 duplicate(s)
delete from public.customers where id in ('864cd4b7-236d-442b-abfd-ea79960c5a17');

-- sonja kosi — keep e018eb71-2c43-4b43-97d4-c63d2dd5ccb6, remove 1 duplicate(s)
delete from public.customers where id in ('1dd96dbd-1f85-40e8-b9bf-c7219979f16a');

-- stjepan knežević — keep 4da56154-5795-4589-9499-6ed3f4abfb76, remove 1 duplicate(s)
delete from public.customers where id in ('980665bb-33f6-4f61-9e2e-ebcc95f6c7c0');

-- stjepan živić — keep 7bc71b5c-55ea-4848-b971-0a3f880fc2d7, remove 1 duplicate(s)
delete from public.customers where id in ('70f00707-2519-4332-b4af-87b4325256e4');

-- sveučilište u zagrebu agronomski fakultet — keep aa658c4c-8972-4f4e-b2a8-e7c9408b80d8, remove 1 duplicate(s)
delete from public.customers where id in ('b2528a66-fea1-49e1-86d5-f4b8ee3067b5');

-- tadej štoka — keep 08ee76f7-8a02-46c3-91d3-ae0f57e8c5fe, remove 1 duplicate(s)
delete from public.customers where id in ('0d7cc759-8245-4aea-a32f-8c7defe8f2d0');

-- tina žgajnar — keep 561b80c6-ad98-49f2-8772-3f762012ac9d, remove 1 duplicate(s)
delete from public.customers where id in ('852c0571-041e-4cc0-9574-781807d335cf');

-- tomislav andabaka — keep fac645d1-c422-4bf3-ab51-8459fbe8a29f, remove 1 duplicate(s)
delete from public.customers where id in ('5d0c1143-02f8-4206-ad74-85ba42362402');

-- tomislav brkanić — keep 0c5ef8b5-62a0-477d-aee0-33a8a56c80a3, remove 1 duplicate(s)
delete from public.customers where id in ('1d9951ef-cd59-466c-bdc9-31f343b6a726');

-- tomislav tukić — keep e38771bb-1416-4ef7-abe1-6c559077cae1, remove 1 duplicate(s)
delete from public.customers where id in ('8a15caa1-d00d-47d5-a995-9f098d4b5bc8');

-- trs udruga — keep f0948b49-758d-4583-8169-6f12e1056447, remove 1 duplicate(s)
delete from public.customers where id in ('3a5adb49-4592-4bc7-b520-8e9e5a2f5c2c');

-- uroš  nadu — keep 0df06a50-c5d1-4211-b37b-945874924b89, remove 1 duplicate(s)
delete from public.customers where id in ('5f165e58-1f8c-4c97-b956-a6058daa9de9');

-- veljko antolić — keep 75df0dd0-1557-49d1-8454-15f7b35f0208, remove 1 duplicate(s)
delete from public.customers where id in ('4a73e9bf-6094-474f-a9e8-1d1aeba876ec');

-- veomir mišković — keep 6ad8c670-6db5-419d-8050-f536ae9f3c93, remove 1 duplicate(s)
delete from public.customers where id in ('a7548756-c305-4e71-b945-47b352b357f0');

-- vina kras — keep 311cae2d-ed0e-466b-908f-fb3ecea649de, remove 1 duplicate(s)
delete from public.customers where id in ('eeacfa85-7aa1-4125-81a8-340e52ea22e0');

-- vina kunčić — keep 57344e1f-803f-4b16-98e3-2a91dd8adb82, remove 1 duplicate(s)
delete from public.customers where id in ('73e4ba8c-cd2c-47ee-a8be-5c96e9b7b17d');

-- vinogradništvo štemberger gregor — keep 7e28fe08-a34e-4189-b838-d4474b1d3124, remove 1 duplicate(s)
delete from public.customers where id in ('b3d97059-a759-4849-9304-e981e2d6f608');

-- vlado  đuranec — keep 2cf37fbd-b02a-41c3-92e6-ae0032d9a6f4, remove 1 duplicate(s)
delete from public.customers where id in ('2b3d6b82-4d71-41f6-86a9-c1c7d265dde6');

-- žan rataj — keep 028b8723-8473-4004-a31b-71cfc5a2c298, remove 1 duplicate(s)
delete from public.customers where id in ('851d8870-6a17-4f55-8561-009616f1fa4b');

-- željko  petrlić — keep d281e3c6-fe6c-4960-9d52-cc09459fcea3, remove 1 duplicate(s)
delete from public.customers where id in ('e518d32c-39bb-4af3-8311-4fdb8607d080');

-- zorislav  brkanić — keep 5c694b33-584c-4c92-8357-585a70efddbe, remove 1 duplicate(s)
delete from public.customers where id in ('268d441a-b3d4-4340-9a23-b51b650de00e');

-- grm novo mesto-center biotehnike in turizma — keep 64bd23f9-2d82-4ba3-936b-7e344bda33b2, remove 1 duplicate(s)
delete from public.customers where id in ('0ded7a88-0a21-4c3b-9f2c-237c1f66125b');

-- peter gönc — keep aa810cf4-e56d-4a0e-af23-b26d2e88fb81, remove 1 duplicate(s)
delete from public.customers where id in ('589efc79-bf43-4b1e-993a-314497a0d3c5');

-- krešimir mijačević — keep 54af52df-ef6c-482f-af7d-c1e386f68ac5, remove 1 duplicate(s)
delete from public.customers where id in ('70ac079b-a80b-4293-945e-cc7bd6054be8');

-- andrej grabnar — keep 8781993c-ed81-4374-b7fa-48e119d216be, remove 1 duplicate(s)
delete from public.customers where id in ('ea004807-845b-4411-9351-0c9fe5c89b67');

-- vočnjak ludina — keep c214110a-f3cb-4bdd-aedd-17d773305caa, remove 1 duplicate(s)
delete from public.customers where id in ('80da03a3-bc6f-4603-b7d2-8b15f380700a');

-- nik jarkovič — keep 95760779-c87b-4c26-abe1-09009748d916, remove 1 duplicate(s)
delete from public.customers where id in ('24215cf2-43d5-4162-b4cc-a4baffdbf62c');

-- dimnik estate d.o.o. — keep ce09028b-1f77-4417-a4aa-d3cb19420a36, remove 1 duplicate(s)
delete from public.customers where id in ('c9815725-8564-4998-81be-906fc386bb7c');

-- agroneretva d.o.o. — keep bb73edc3-ac10-42f8-8011-49b22958ff2f, remove 1 duplicate(s)
delete from public.customers where id in ('f04bba7b-d1c3-49a4-8e6e-7db7ae3fd381');

commit;
