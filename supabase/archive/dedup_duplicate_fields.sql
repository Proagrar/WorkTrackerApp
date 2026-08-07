-- ============================================================
-- WorkTracker — Dedupe fields duplicated within a single customer
-- Same root cause as the earlier customer dedup (two 2026-04 bulk
-- imports), but for these customers only the field rows were
-- duplicated, not the customer row itself. 42 pairs across 9
-- customers, every pair verified identical (name + area_ha).
-- ============================================================

begin;

delete from public.fields where id = 'efd8904b-f9b6-4d37-b03c-f27e96ff8b20'; -- duplicate of be58ee38-dd51-4721-9623-f47cecf5499e
delete from public.fields where id = '36072a31-c672-4516-a58e-03b58a17ff0f'; -- duplicate of 889aa139-8007-4c0f-b0aa-15fe5d421229
delete from public.fields where id = '137d10d3-7551-438e-b23f-f339d7d6f70a'; -- duplicate of 14dda3cf-2a5c-41be-841f-79d3a3ccbda4
delete from public.fields where id = '57d6803b-7d74-4ab5-97ff-020acc4a1c35'; -- duplicate of 5a47a00f-7b64-48ba-ae8a-d7a4a9cc5c71
delete from public.fields where id = '1ffa3a43-3b18-49df-ade5-26a8e43c569c'; -- duplicate of 5fdbc14e-7b59-4802-a2cb-203121324246
delete from public.fields where id = '70eb549c-55cc-46b8-b3d2-e1138b3093d8'; -- duplicate of a98a949b-fdd8-444f-ba8e-c1c5737325fc
delete from public.fields where id = '731a3281-291c-47e4-ae8c-712d57093612'; -- duplicate of 6caae86b-8cdc-484e-a94b-9394cad3b7f4
delete from public.fields where id = '3d8824de-a41a-47cb-ac51-aea8922ca976'; -- duplicate of 9efca2b4-2d79-4eb0-98cb-23caf9c8e63b
delete from public.fields where id = 'e184d2fe-6d14-483b-80b4-9a9b5ec7f560'; -- duplicate of 14017347-1b55-445e-9567-d4663e6789d9
delete from public.fields where id = 'd9adb1b6-4458-4ccd-8d01-9a7ce02ea0a0'; -- duplicate of e68b65c8-d040-4323-9573-a9508f401b47
delete from public.fields where id = 'f35c40f9-5dbd-41a9-81a2-311529bc2b0f'; -- duplicate of 267d1d73-e22e-4451-b392-cdbfb4125896
delete from public.fields where id = '6b3b8e37-6057-46da-9d5c-7e04e0e0ea74'; -- duplicate of 40505848-d51b-44ac-91de-41ba3964a855
delete from public.fields where id = 'dc5a473b-052f-46d1-9590-c2539347302f'; -- duplicate of b5309182-480c-4919-9a29-d71f8fa813d7
delete from public.fields where id = 'dc6738f2-db94-46b7-9406-edc2dd75da68'; -- duplicate of d9d0742d-0e96-4806-9462-f8907f22ffd8
delete from public.fields where id = 'd026a14a-13b9-4fb8-94fd-2f324a8c3339'; -- duplicate of e8dbd232-2943-4d91-be07-2d88469c930f
delete from public.fields where id = 'f4e00b2d-439b-4e11-8cff-f9194645b18e'; -- duplicate of 541b19c3-f24d-4225-afbd-ecf002ee5665
delete from public.fields where id = 'd5abfa7a-9dd7-49e9-bb5a-8e8d8617f017'; -- duplicate of 270709be-3988-4b52-8318-8b245dc7c484
delete from public.fields where id = 'd1e4da12-0bf6-4af0-8f25-6402bdadef15'; -- duplicate of 75a29054-f6d7-4b8b-aec5-8ae311f34ddd
delete from public.fields where id = 'f2c5b56d-bc5d-4134-bc20-50b6333e459c'; -- duplicate of 5c72925e-9790-47f2-9458-11007647aea6
delete from public.fields where id = 'eeeb120e-8fdf-4191-bcc1-3f0068a31ebc'; -- duplicate of 9dcdc804-e4b2-4c30-9e07-7248a360b818
delete from public.fields where id = '95366bb2-e91d-4294-84be-bb5240604deb'; -- duplicate of aee68c4c-c006-4019-88ea-d4e02b56ccc1
delete from public.fields where id = '3c8d3c0f-a4ab-4dc8-a5f5-57a776923342'; -- duplicate of 73458c0a-4816-452a-bf3b-3b9e3e00d514
delete from public.fields where id = 'daa638d4-f997-4915-9e91-c3e48c9e80ad'; -- duplicate of 18065f3c-32c8-4ade-bf2b-37e7fee8c651
delete from public.fields where id = '6f05ded6-199a-4324-8868-438b1f8c1822'; -- duplicate of d91fd103-07d9-45bf-ade9-081b5a46f1f1
delete from public.fields where id = 'a7a3cc93-d72d-43ee-a83a-ad74f9be4753'; -- duplicate of 4fb0e32d-c58a-415a-9acc-826e8b2490d9
delete from public.fields where id = '96c1bf6a-62d0-4d02-85b9-9d6941aaeaf7'; -- duplicate of cfdab8fb-8918-47f7-b1bc-0bbf26020a46
delete from public.fields where id = 'd44645ea-62b7-44b9-bde7-864446067687'; -- duplicate of 150d033d-2023-4daa-afdc-2bf549dde653
delete from public.fields where id = '6fbb1b11-520b-4390-bba1-c55913d915c8'; -- duplicate of 56cfc4b2-01a7-49ba-9231-b6e583fa17e9
delete from public.fields where id = '0edb316d-41c1-4dbc-af4c-7dc8939cd430'; -- duplicate of 77e89b7b-abe3-46cd-8aab-ed4d74d9a8eb
delete from public.fields where id = '44e51f1b-1abe-409b-aba3-bd121935d39b'; -- duplicate of cebba362-d1db-47b1-81a6-451c0a542473
delete from public.fields where id = '2c89f8f6-6f59-4e0b-98df-af019891e857'; -- duplicate of 3d3eb902-0969-4ddf-a7ca-2586d88d5794
delete from public.fields where id = '79965475-f531-4e84-b285-3570de4b05ed'; -- duplicate of d75ca99d-f572-4ba3-b35e-64b7f05afacb
delete from public.fields where id = '589eb761-c6d0-4776-a9de-6decfeb81508'; -- duplicate of 7aa0b87f-16f0-421f-9add-147703d7c6b4
delete from public.fields where id = 'ac0e0ec6-18c5-47e8-a26d-ff7c4a657e36'; -- duplicate of 3453ded5-63f3-4bfc-9dfe-3d7cedb4c7d5
delete from public.fields where id = '2d2e8bb6-eb83-46e4-93e2-947c696a616a'; -- duplicate of bf562c70-99f8-4ef5-867b-8ecbbe874f25
delete from public.fields where id = 'c9a1a3b9-8da2-4eed-8d23-433ace275313'; -- duplicate of 57183077-debd-40d1-8637-09b21276d257 (Jani Brezovnik)
delete from public.fields where id = 'df42bedb-683c-4b1b-93ad-4f962a30c18d'; -- duplicate of 7321fab6-4895-446f-b17c-14d099747886 (Boštjan Martinec)
delete from public.fields where id = 'c7a7265d-8bb2-4af7-8db4-dcd52454e98e'; -- duplicate of 910aa50e-53f5-4689-ad6c-336110eb83f8 (Veomir Mišković)
delete from public.fields where id = '9be8f003-0a9f-452f-a635-78a241c22cda'; -- duplicate of 810cfdb9-a9f1-44cc-bd41-99f3dab9e2bb (Martinčič d.o.o.)
delete from public.fields where id = '80d78d26-f33c-4346-a49b-497944516b78'; -- duplicate of 3cfe1675-f5b1-4cfd-8c98-466c82e8cd23 (Matej Brezovnik)
delete from public.fields where id = '1dc665f6-b6b0-49c0-bdcf-db3268edb003'; -- duplicate of 0672c4ef-71ac-4560-869e-95d8925f3a03 (Grega Guzej)
delete from public.fields where id = '980a8975-86e3-4b12-96cf-7e513a6d60dd'; -- duplicate of 03fb9323-9dce-4c26-8513-f13a1a5944b9 (Matjaž Urek)

commit;
