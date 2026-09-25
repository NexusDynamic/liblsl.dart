window.BENCHMARK_DATA = {
  "lastUpdate": 1790376722483,
  "repoUrl": "https://github.com/NexusDynamic/liblsl.dart",
  "entries": {
    "liblsl.dart benchmarks": [
      {
        "commit": {
          "author": {
            "email": "zeyus@zeyus.com",
            "name": "zeyus",
            "username": "zeyus"
          },
          "committer": {
            "email": "zeyus@zeyus.com",
            "name": "zeyus",
            "username": "zeyus"
          },
          "distinct": true,
          "id": "14256750c4a3085a91626b16afc1def031112f66",
          "message": "Stop tracking benchmark output",
          "timestamp": "2026-09-25T15:01:45+02:00",
          "tree_id": "d22a5f3c33378583dea923f99367e70d247fcae6",
          "url": "https://github.com/NexusDynamic/liblsl.dart/commit/14256750c4a3085a91626b16afc1def031112f66"
        },
        "date": 1790341528449,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p50",
            "value": 110.13003124560328,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p95",
            "value": 128.57224609774676,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p99",
            "value": 212.4135078247491,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz time_per_sample",
            "value": 2001.33422281521,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 10238.05419532664,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19485.620726555906,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20249.096273431634,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p50",
            "value": 72.19854688855776,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p95",
            "value": 87.67574999524186,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p99",
            "value": 100.13160937205612,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz time_per_sample",
            "value": 2001.33422281521,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 9863.093539053125,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19099.26363282466,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 19945.474749988534,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p50",
            "value": 179.6468437476051,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p95",
            "value": 241.80452342648096,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p99",
            "value": 272.82704687081605,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz time_per_sample",
            "value": 2001.33422281521,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 10387.621710947315,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19759.624062487546,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20498.23555469743,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "zeyus@zeyus.com",
            "name": "zeyus",
            "username": "zeyus"
          },
          "committer": {
            "email": "zeyus@zeyus.com",
            "name": "zeyus",
            "username": "zeyus"
          },
          "distinct": true,
          "id": "765af1307e03f8e63d6a449d6c4a2d55d5e39c32",
          "message": "fix android build",
          "timestamp": "2026-09-25T15:11:18+02:00",
          "tree_id": "ce72743e526dd790799c05f38400bad3ae8b1196",
          "url": "https://github.com/NexusDynamic/liblsl.dart/commit/765af1307e03f8e63d6a449d6c4a2d55d5e39c32"
        },
        "date": 1790342098141,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p50",
            "value": 106.66281249882559,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p95",
            "value": 132.90339063587453,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p99",
            "value": 222.76759375472466,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz time_per_sample",
            "value": 2001.33422281521,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 10170.284046864708,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19168.798453137017,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20115.974929694858,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p50",
            "value": 70.3798281165291,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p95",
            "value": 85.74410938422261,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p99",
            "value": 99.48071874532616,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz time_per_sample",
            "value": 2001.33422281521,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 10277.502781264047,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19276.831843740183,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20145.951296882457,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p50",
            "value": 179.667281258844,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p95",
            "value": 250.07852343605919,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p99",
            "value": 293.5150468772463,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz time_per_sample",
            "value": 2001.33422281521,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 10218.877757807832,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19367.898812504336,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20338.291296866373,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "zeyus@zeyus.com",
            "name": "zeyus",
            "username": "zeyus"
          },
          "committer": {
            "email": "zeyus@zeyus.com",
            "name": "zeyus",
            "username": "zeyus"
          },
          "distinct": true,
          "id": "739ae0200b217d4995327111fdf7e8b0a6f081bf",
          "message": "updated some readme / info",
          "timestamp": "2026-09-25T16:31:31+02:00",
          "tree_id": "ef529270cd3d77b2e4ad4f44f1290dc64894cbfa",
          "url": "https://github.com/NexusDynamic/liblsl.dart/commit/739ae0200b217d4995327111fdf7e8b0a6f081bf"
        },
        "date": 1790346899493,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p50",
            "value": 106.32043751002129,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p95",
            "value": 130.647109358506,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p99",
            "value": 214.53385937775238,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz time_per_sample",
            "value": 2001.33422281521,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 10046.569640621783,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19262.517703111826,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20022.437125021497,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p50",
            "value": 68.31468749624037,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p95",
            "value": 87.79842187323084,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p99",
            "value": 96.78776564214786,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz time_per_sample",
            "value": 2001.33422281521,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 10216.304406242216,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19377.300421865584,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20064.180312488133,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p50",
            "value": 173.54792186097256,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p95",
            "value": 241.4317031025348,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p99",
            "value": 296.4449531077662,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz time_per_sample",
            "value": 2001.33422281521,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 10245.659359384263,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19254.799828104296,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20247.237109401794,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "zeyus@zeyus.com",
            "name": "zeyus",
            "username": "zeyus"
          },
          "committer": {
            "email": "zeyus@zeyus.com",
            "name": "zeyus",
            "username": "zeyus"
          },
          "distinct": true,
          "id": "6646e34d00c8b446e5513f192057af2392b3479a",
          "message": "update submodule name",
          "timestamp": "2026-09-25T16:40:59+02:00",
          "tree_id": "e5b19b6c0b0350e7a1680f882740a39bd91f772e",
          "url": "https://github.com/NexusDynamic/liblsl.dart/commit/6646e34d00c8b446e5513f192057af2392b3479a"
        },
        "date": 1790347462695,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p50",
            "value": 69.30305077901266,
            "unit": "us",
            "extra": "n=4500"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p95",
            "value": 107.29939843656666,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p99",
            "value": 176.33647266279695,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz time_per_sample",
            "value": 2000,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 9954.14689063523,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19120.026460939243,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 19992.43535155415,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p50",
            "value": 72.75188281141709,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p95",
            "value": 92.06648437043441,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p99",
            "value": 100.11971875201198,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz time_per_sample",
            "value": 2001.33422281521,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 10010.108539063367,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19089.3457656216,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 19840.685445302595,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p50",
            "value": 124.42935937428956,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p95",
            "value": 151.51236718224936,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p99",
            "value": 171.9345937374328,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz time_per_sample",
            "value": 2001.33422281521,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 10249.499187494848,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19434.754374998418,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20273.857062505842,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "zeyus@zeyus.com",
            "name": "zeyus",
            "username": "zeyus"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6aedf52e1dbd9896aef80341135a4af228db6cae",
          "message": "Merge pull request #26 from NexusDynamic/feature/viewer-relay-docs\n\n[lsl_viewer] [lsl_tools] app fixes + relay",
          "timestamp": "2026-09-26T00:48:42+02:00",
          "tree_id": "424e4facf6e01a7403ebc5fc1b33e649f752af79",
          "url": "https://github.com/NexusDynamic/liblsl.dart/commit/6aedf52e1dbd9896aef80341135a4af228db6cae"
        },
        "date": 1790376719659,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p50",
            "value": 75.52203123850632,
            "unit": "us",
            "extra": "n=4500"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p95",
            "value": 108.53428125301434,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p99",
            "value": 185.69368751286675,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz time_per_sample",
            "value": 2000,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 10176.315468697794,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19272.507999971822,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20112.334750024274,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p50",
            "value": 55.24684377178346,
            "unit": "us",
            "extra": "n=4500"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p95",
            "value": 85.24121869868395,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p99",
            "value": 200.4235312824676,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz time_per_sample",
            "value": 2000,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 10165.593406213702,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19124.632718785506,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 19876.256562497474,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p50",
            "value": 130.26956253270328,
            "unit": "us",
            "extra": "n=4500"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p95",
            "value": 191.06237505184254,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p99",
            "value": 247.35543752285594,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz time_per_sample",
            "value": 2000,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 10230.675625052754,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19446.361750055985,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20365.17753128919,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          }
        ]
      }
    ]
  }
}