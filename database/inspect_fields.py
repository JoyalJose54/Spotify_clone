import firebase_admin
from firebase_admin import credentials, firestore
from collections import Counter

cred = credentials.Certificate("firebase-key.json")
if not firebase_admin._apps:
    firebase_admin.initialize_app(cred)
db = firestore.client()

tracks = list(db.collection('tracks').stream())
print(f"Total tracks found: {len(tracks)}")

field_counter = Counter()
samples = {}

for doc in tracks:
    d = doc.to_dict()
    for k, v in d.items():
        field_counter[k] += 1
        if k not in samples:
            samples[k] = str(v)[:40]

print("\n--- ALL FIELDS AND OCCURRENCES ---")
for field, count in field_counter.most_common():
    print(f"{field:<25}: in {count}/{len(tracks)} tracks | sample: {samples[field]}")
