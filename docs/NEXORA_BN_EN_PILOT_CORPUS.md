# NEXORA Bengali ↔ English Pilot Corpus

**Status:** seed evaluation set; NOT human-validated and NOT model output.  
**Purpose:** compare IndicTrans2 and Argos on identical, non-private marketplace/chat examples.  
**Directions:** each row is one parallel pair. Run Bengali→English using the Bengali text as input and English as reference; run English→Bengali in the reverse direction.  
**Privacy:** synthetic/publicly authored examples only. Never copy Buyer/Seller private messages, names, phone numbers, addresses, credentials or live order data into this corpus.

## Review gate before scoring

Two independent Bangla-English reviewers must first validate each reference pair for meaning equivalence and naturalness. Correct the reference only by documented reviewer agreement; preserve the original version in review notes. If reviewers disagree materially, mark the case disputed and exclude it from aggregate scoring until resolved. These seed references are not ground truth merely because they appear here.

## Parallel test cases

| ID | Coverage | বাংলা reference | English reference |
|---|---|---|---|
| T01 | Formal | আপনার অর্ডারটি গ্রহণ করা হয়েছে। | Your order has been accepted. |
| T02 | Negation | পণ্যটি এখন স্টকে নেই। | The product is not in stock right now. |
| T03 | Quantity | আমরা ৫০০ কেজি চাল সরবরাহ করতে পারব। | We can supply 500 kilograms of rice. |
| T04 | Price/currency | প্রতি পিসের দাম ৯৫ টাকা, পরিবহন খরচ আলাদা। | The price is BDT 95 per piece; transportation cost is separate. |
| T05 | Counter-offer | আপনার প্রস্তাব ৯০ টাকা। আমরা প্রতি পিস ৯৫ টাকা দিতে পারি। | Your offer is BDT 90. We can offer BDT 95 per piece. |
| T06 | Required date | পণ্যটি ২০২৬ সালের ২০ ডিসেম্বরের মধ্যে প্রয়োজন। | The product is required by 20 December 2026. |
| T07 | Question | আপনি কি আগামীকাল পণ্যটি পাঠাতে পারবেন? | Can you dispatch the product tomorrow? |
| T08 | Delivery | চালানটি গন্তব্যে পৌঁছালে ক্রেতাকে OTP দিয়ে গ্রহণ নিশ্চিত করতে হবে। | When the shipment reaches its destination, the buyer must confirm receipt using an OTP. |
| T09 | Specification | কাপড়টি ১০০% সুতি এবং প্রতি মিটারে ২০০ গ্রাম। | The fabric is 100% cotton and weighs 200 grams per meter. |
| T10 | Quality | পাঠানোর আগে অনুগ্রহ করে প্রতিটি পণ্যের মান পরীক্ষা করুন। | Please check the quality of every item before dispatch. |
| T11 | Availability | এই সপ্তাহে আমাদের উৎপাদন সক্ষমতা সীমিত, তবে পরের সপ্তাহে সরবরাহ বাড়ানো যাবে। | Our production capacity is limited this week, but supply can be increased next week. |
| T12 | Negotiation | ৯৫ টাকা গ্রহণ করতে পারছি না। আপনি কি ৯৩ টাকা করতে পারবেন? | I cannot accept BDT 95. Can you make it BDT 93? |
| T13 | Ambiguity control | অর্ডারটি বাতিল করবেন না; আমি শুধু পরিমাণ পরিবর্তন করতে চাই। | Do not cancel the order; I only want to change the quantity. |
| T14 | Business chat | নমুনা অনুমোদনের পর আমরা বাকি পণ্য উৎপাদন শুরু করব। | We will start producing the remaining items after the sample is approved. |
| T15 | Destination | পণ্যটি চট্টগ্রাম বন্দরে পাঠাতে হবে, ঢাকায় নয়। | The product must be sent to Chattogram Port, not Dhaka. |
| T16 | File/action | অনুগ্রহ করে স্বাক্ষর করা চালানটির PDF এখানে পাঠান। | Please send the signed invoice PDF here. |
| T17 | Short informal | ঠিক আছে, আজ বিকেলের মধ্যে জানাচ্ছি। | Okay, I will let you know by this afternoon. |
| T18 | Clarification | আপনি কি মোট ১,২০০ পিস বোঝাচ্ছেন, নাকি প্রতি কার্টনে ১,২০০ পিস? | Do you mean 1,200 pieces in total, or 1,200 pieces per carton? |
| T19 | Date + time | মিটিংটি ১৫ জানুয়ারি ২০২৭ সকাল ১০টায় (বাংলাদেশ সময়) হবে। | The meeting will be at 10:00 AM Bangladesh time on 15 January 2027. |
| T20 | IDs/tokens | পণ্যের ID NX-2048 এবং চালানের নম্বর INV-7781 অপরিবর্তিত রাখুন। | Keep product ID NX-2048 and invoice number INV-7781 unchanged. |
| T21 | Refund | পণ্য ক্ষতিগ্রস্ত হলে ছবি পাঠান; যাচাইয়ের পর ফেরতের ব্যবস্থা করা হবে। | If the product is damaged, send a photo; a refund will be arranged after verification. |
| T22 | Partial supply | এখন ৩০০ পিস পাঠান এবং বাকি ২০০ পিস ৫ দিনের মধ্যে পাঠান। | Send 300 pieces now and the remaining 200 pieces within 5 days. |
| T23 | Bangla-English mixed terms | MOQ ৫০ পিস, তবে sample order নেওয়া হবে না। | The MOQ is 50 pieces, but sample orders will not be accepted. |
| T24 | Tone/context | দুঃখিত, আগের বার্তায় পরিমাণটি ভুল লেখা হয়েছিল। সঠিক পরিমাণ ৮০ পিস। | Sorry, the quantity was written incorrectly in the previous message. The correct quantity is 80 pieces. |

## Protected-token checks

For every output, compare these values with the source and reference. Mark any unintended change as a critical error:
- Numbers and quantities: 500, 95, 90, 93, 1,200, 300, 200, 80
- Currency: BDT / টাকা
- Dates and time: 20 December 2026; 15 January 2027; 10:00 AM; 5 days
- Units: kg/kilograms, meter, pieces, carton
- IDs: NX-2048, INV-7781
- Negation and contrast: not, do not, only, not Dhaka, remaining

## Run protocol

1. Freeze this corpus version before testing; record its Git commit and model checkpoint IDs/revisions.
2. Have two independent bilingual reviewers validate the reference pairs before model scoring.
3. Run all 24 cases in both directions for each candidate using the same preprocessing and decoding settings. Do not silently normalize numbers, dates, names or punctuation differently between models.
4. Record raw output exactly. Do not edit model output before review.
5. Each reviewer independently scores each output: meaning preservation (0–4), fluency (0–4), omissions/additions (0–4; higher means none/minimal), protected-token accuracy (pass/fail), and critical negation/amount/date error (yes/no).
6. Resolve reviewer disagreement and report per-direction results separately. With only 24 examples per direction, this is a screening pilot, not statistically conclusive.
7. If tooling is available, calculate chrF++ and COMET using the validated references; report metric package/version and do not use BLEU alone as an acceptance decision.
8. Compare CPU/GPU, peak RAM/VRAM, model download size, cold-start, per-message latency, throughput and hosting cost on the intended server.

## Results record (leave blank until actual inference)

| Candidate / exact revision | Direction | Cases run | Human review | chrF++ | COMET | Critical errors | Latency / resource notes |
|---|---|---:|---|---:|---:|---:|---|
| IndicTrans2 | bn→en | — | Not run | — | — | — | — |
| IndicTrans2 | en→bn | — | Not run | — | — | — | — |
| Argos | bn→en | — | Not run | — | — | — | — |
| Argos | en→bn | — | Not run | — | — | — | — |

**Current conclusion:** no inference has been executed; no winner or quality score is claimed. Production translation remains disabled. This corpus is only the repeatable input/reference foundation for a later controlled run.
