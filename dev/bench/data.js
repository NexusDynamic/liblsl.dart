window.BENCHMARK_DATA = {
  "lastUpdate": 1791541308063,
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
          "id": "3fa21530f780d161d64afc23117ac66f57205cb1",
          "message": "[lsl_viewer] version bump",
          "timestamp": "2026-09-26T00:52:24+02:00",
          "tree_id": "3b81183817101e1f4bc8d93ee8e5203904c75a5c",
          "url": "https://github.com/NexusDynamic/liblsl.dart/commit/3fa21530f780d161d64afc23117ac66f57205cb1"
        },
        "date": 1790376953095,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p50",
            "value": 103.88200780653278,
            "unit": "us",
            "extra": "n=4499"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p95",
            "value": 123.62077345073885,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p99",
            "value": 200.39104296643018,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz time_per_sample",
            "value": 2000.4445432318294,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 10074.131140612508,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19149.02305469468,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20158.092101553393,
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
            "value": 66.41903124204873,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p95",
            "value": 82.58837499397487,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p99",
            "value": 97.34415624507164,
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
            "value": 10312.236476551107,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19324.358945311815,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20177.551421880933,
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
            "value": 175.2879375089833,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p95",
            "value": 238.20160936338652,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p99",
            "value": 291.0866953129698,
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
            "value": 10440.92043750311,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19431.21882030141,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20381.986976559572,
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
          "id": "89fd62da4118b71d338e562439cb9f298e96cef4",
          "message": "added android screenshot",
          "timestamp": "2026-09-27T15:03:34+02:00",
          "tree_id": "ef593e1ce619feadff953b63c083ab6c77e66dd2",
          "url": "https://github.com/NexusDynamic/liblsl.dart/commit/89fd62da4118b71d338e562439cb9f298e96cef4"
        },
        "date": 1790514416882,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p50",
            "value": 44.9873203081097,
            "unit": "us",
            "extra": "n=4500"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p95",
            "value": 66.49267187697205,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p99",
            "value": 108.73853906900877,
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
            "value": 10203.237515611363,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19320.837601554784,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20060.23203125551,
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
            "value": 35.01809374029108,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p95",
            "value": 55.403781260565665,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p99",
            "value": 64.26415623650428,
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
            "value": 9985.330421869776,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19391.81870312723,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20030.063421870636,
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
            "value": 79.59932031553762,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p95",
            "value": 108.25259374769303,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p99",
            "value": 288.2232578258481,
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
            "value": 10053.691093759198,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19243.78710938868,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20180.937343752703,
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
          "id": "bffbb2c89c6d7fc4b65000dc10f086cfba6907e8",
          "message": "github readme formatting",
          "timestamp": "2026-09-27T15:04:48+02:00",
          "tree_id": "14714e007cbe0513546f802daabff69befc7652e",
          "url": "https://github.com/NexusDynamic/liblsl.dart/commit/bffbb2c89c6d7fc4b65000dc10f086cfba6907e8"
        },
        "date": 1790514496534,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p50",
            "value": 105.65366015669042,
            "unit": "us",
            "extra": "n=4499"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p95",
            "value": 127.36639843069497,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p99",
            "value": 217.2322968760909,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz time_per_sample",
            "value": 2000.4445432318294,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 10008.888679692518,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19099.737640630112,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 19966.24758592702,
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
            "value": 68.44998438282346,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p95",
            "value": 84.53945312680844,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p99",
            "value": 96.81167188091422,
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
            "value": 10342.94625000598,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19310.366281246163,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20168.224726575092,
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
            "value": 171.02921876244181,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p95",
            "value": 243.90148436737036,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p99",
            "value": 283.92943750077393,
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
            "value": 10483.292367183594,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19510.212234365554,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20275.290617178143,
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
          "id": "4e4e7962885436f980d0b3c83052af71d144d982",
          "message": "github readme formatting",
          "timestamp": "2026-09-27T15:05:45+02:00",
          "tree_id": "4a137428d0e16e4adb804660e0f781e3e24e1f58",
          "url": "https://github.com/NexusDynamic/liblsl.dart/commit/4e4e7962885436f980d0b3c83052af71d144d982"
        },
        "date": 1790514558708,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p50",
            "value": 84.27595312809899,
            "unit": "us",
            "extra": "n=4498"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p95",
            "value": 117.41220313865597,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p99",
            "value": 175.3555234245141,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz time_per_sample",
            "value": 2000.8892841262784,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 10281.91170311743,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19299.952632820805,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20165.522500008137,
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
            "value": 92.62327344572441,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p95",
            "value": 119.92142970029818,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p99",
            "value": 128.68797657006326,
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
            "value": 10291.513601572433,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19487.787031238215,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20070.395304685462,
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
            "value": 147.28695313692697,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p95",
            "value": 184.63558592429763,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p99",
            "value": 213.1289375029155,
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
            "value": 10338.891093738312,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19513.64387500121,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20459.399218736962,
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
          "id": "5dfc6f603b003ba4893d601f27e458408064e51e",
          "message": "github readme formatting",
          "timestamp": "2026-09-27T15:06:31+02:00",
          "tree_id": "edf6b2dc09dec56c1c8cea3ea1e1b7bdbed0a444",
          "url": "https://github.com/NexusDynamic/liblsl.dart/commit/5dfc6f603b003ba4893d601f27e458408064e51e"
        },
        "date": 1790514604828,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p50",
            "value": 90.35075001406767,
            "unit": "us",
            "extra": "n=4498"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p95",
            "value": 133.67408593012442,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p99",
            "value": 198.8016015559424,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz time_per_sample",
            "value": 2000.8892841262784,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 10075.139453135762,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19405.18767969479,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20104.503203128843,
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
            "value": 67.76374218020464,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p95",
            "value": 119.1198203116528,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p99",
            "value": 203.44785937709275,
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
            "value": 10010.561015633357,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19183.102085946757,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20069.217265614723,
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
            "value": 139.4304843813643,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p95",
            "value": 193.92428905007364,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p99",
            "value": 290.40263279966894,
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
            "value": 10793.539265620211,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19981.83307813406,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20447.789507812784,
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
          "id": "20a226318b2e076488affd6cf750c96111f1c59d",
          "message": "github readme formatting",
          "timestamp": "2026-09-27T15:09:46+02:00",
          "tree_id": "f15b69410338fc488cab06f9fbfb9d82d1ec58ad",
          "url": "https://github.com/NexusDynamic/liblsl.dart/commit/20a226318b2e076488affd6cf750c96111f1c59d"
        },
        "date": 1790514792307,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p50",
            "value": 68.83280859426577,
            "unit": "us",
            "extra": "n=4499"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p95",
            "value": 106.10439844072062,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p99",
            "value": 160.31271874794584,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz time_per_sample",
            "value": 2000.4445432318294,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 10008.800914050653,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19343.204140625403,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 19839.438039070956,
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
            "value": 50.733328123442334,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p95",
            "value": 92.08146875039347,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p99",
            "value": 104.9873281147029,
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
            "value": 9945.326265636822,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19180.92154687656,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20014.571359382673,
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
            "value": 121.85340625592289,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p95",
            "value": 153.87921092724355,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p99",
            "value": 248.5501484272845,
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
            "value": 10386.139710931275,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19746.092359383736,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20358.390187510624,
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
          "id": "a6646756ed9b6f0a12fdb2b1642cddde221ce171",
          "message": "[webrtc_coordinator_flutter] version bump to match webrtc_coordinator",
          "timestamp": "2026-09-27T21:06:27+02:00",
          "tree_id": "1fca351c696f4c1685a32390b1aaa36e0ef5123d",
          "url": "https://github.com/NexusDynamic/liblsl.dart/commit/a6646756ed9b6f0a12fdb2b1642cddde221ce171"
        },
        "date": 1790536204281,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p50",
            "value": 118.72253907085906,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p95",
            "value": 141.3990781315988,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p99",
            "value": 254.76509375721434,
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
            "value": 10065.02064842607,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19235.438375005742,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 19888.095398442827,
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
            "value": 77.78580467743268,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p95",
            "value": 95.32128905220816,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p99",
            "value": 116.17797656526818,
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
            "value": 10312.91560937575,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19360.17392188205,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20087.797437497557,
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
            "value": 180.93167187771542,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p95",
            "value": 251.5965312568369,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p99",
            "value": 312.4606718643008,
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
            "value": 10499.561523431566,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19382.143562495457,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20435.857218757294,
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
          "id": "786aa31c4d070019e5f97cf50477ecb277ed7841",
          "message": "[webrtc_coordinator_flutter] fix hang due to connection not reporting open",
          "timestamp": "2026-09-27T21:49:59+02:00",
          "tree_id": "4ecdfd38447b266af334541f247ad064ac5388e2",
          "url": "https://github.com/NexusDynamic/liblsl.dart/commit/786aa31c4d070019e5f97cf50477ecb277ed7841"
        },
        "date": 1790538805436,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p50",
            "value": 97.98637501035046,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p95",
            "value": 119.5756093466116,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p99",
            "value": 196.19462500486406,
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
            "value": 10139.99121875031,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19252.111890637025,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20133.936359400195,
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
            "value": 63.350671894113475,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p95",
            "value": 82.27973438579284,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p99",
            "value": 89.0523281213973,
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
            "value": 10226.106453103512,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19261.2042343967,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20041.202312484074,
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
            "value": 165.81984374397507,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p95",
            "value": 223.35207813739544,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p99",
            "value": 257.98579684988,
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
            "value": 10108.404374989277,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19201.211078097913,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20313.61415623678,
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
          "id": "559518df2fe3afef25f1a2f4ef545dd8481bf0c0",
          "message": "Merge pull request #28 from NexusDynamic/feature/analysis-revisited\n\n[liblsl] Event-driven inlets",
          "timestamp": "2026-10-08T10:56:08+02:00",
          "tree_id": "c703f904bc2f141a19e62d585fb7063d85f55d1a",
          "url": "https://github.com/NexusDynamic/liblsl.dart/commit/559518df2fe3afef25f1a2f4ef545dd8481bf0c0"
        },
        "date": 1791450015413,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p50",
            "value": 66.22629955188586,
            "unit": "us",
            "extra": "n=4498"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p95",
            "value": 103.71997328206817,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p99",
            "value": 139.0503279026234,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz time_per_sample",
            "value": 2000.8892841262784,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 165.51694824329388,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 200.42429969180375,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 250.2504152914753,
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
            "value": 73.09557716439485,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p95",
            "value": 90.54388965523685,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p99",
            "value": 94.77577782490698,
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
            "value": 134.4042956645808,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 159.7842828289231,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 213.77158935820262,
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
            "value": 123.51502991236885,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p95",
            "value": 150.18941076050396,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p99",
            "value": 170.83994072208952,
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
            "value": 196.6587685160448,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 236.6649826512912,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 578.6204557409746,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz latency_p50",
            "value": 87.46531878500718,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz latency_p95",
            "value": 96.04680565189483,
            "unit": "us"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz latency_p99",
            "value": 101.58850241737127,
            "unit": "us"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz time_per_sample",
            "value": 2001.33422281521,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 130.16100348295367,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 162.2819600868297,
            "unit": "us"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 179.00858910024908,
            "unit": "us"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "dev@zeyus.com",
            "name": "zeyus",
            "username": "zeyus"
          },
          "committer": {
            "email": "dev@zeyus.com",
            "name": "zeyus",
            "username": "zeyus"
          },
          "distinct": true,
          "id": "5b279ca900f1cb14626caeb5971ea0045377c576",
          "message": "prepare for releases, additional packages, only test tag if not tested",
          "timestamp": "2026-10-08T12:23:30+02:00",
          "tree_id": "b7c555a96e37e7fd27d88ede77bd307a12a8f4e2",
          "url": "https://github.com/NexusDynamic/liblsl.dart/commit/5b279ca900f1cb14626caeb5971ea0045377c576"
        },
        "date": 1791455239915,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p50",
            "value": 43.083395013354675,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p95",
            "value": 57.15427465702305,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p99",
            "value": 121.15837586179623,
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
            "value": 78.54433422949114,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 147.41526001671446,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 378.863652997552,
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
            "value": 48.16489379777522,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p95",
            "value": 54.685767821638365,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p99",
            "value": 63.05423241315111,
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
            "value": 98.02517450907544,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 246.37534417593088,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 607.7799453123589,
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
            "value": 77.25414258175078,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p95",
            "value": 104.59603268486717,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p99",
            "value": 337.702374622495,
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
            "value": 243.06440076315994,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 282.14651246116773,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 662.8936741890357,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz latency_p50",
            "value": 54.04016326338024,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz latency_p95",
            "value": 63.58733429578933,
            "unit": "us"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz latency_p99",
            "value": 149.68069712040233,
            "unit": "us"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz time_per_sample",
            "value": 2001.33422281521,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 117.8915005084491,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 157.01653580890707,
            "unit": "us"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 214.4541765574104,
            "unit": "us"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "dev@zeyus.com",
            "name": "zeyus",
            "username": "zeyus"
          },
          "committer": {
            "email": "dev@zeyus.com",
            "name": "zeyus",
            "username": "zeyus"
          },
          "distinct": true,
          "id": "67cae512fb6fe02b9e7e80a3866319627ce298ea",
          "message": "lower test constraint to prevent issues with downstream implementations",
          "timestamp": "2026-10-08T12:42:32+02:00",
          "tree_id": "a135b3313d4ea0c990b07db31fadff44d7e16ac0",
          "url": "https://github.com/NexusDynamic/liblsl.dart/commit/67cae512fb6fe02b9e7e80a3866319627ce298ea"
        },
        "date": 1791456398654,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p50",
            "value": 68.60804359121175,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p95",
            "value": 95.14972924762333,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p99",
            "value": 155.31087939280042,
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
            "value": 130.55896263836075,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 263.615556377772,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 301.0391926068223,
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
            "value": 45.596379777634866,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p95",
            "value": 52.49338843782425,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p99",
            "value": 77.27639575705325,
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
            "value": 116.98464550136123,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 234.75444103837617,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 250.59998998244737,
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
            "value": 110.56648514795597,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p95",
            "value": 162.67362963162668,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p99",
            "value": 212.3489049949967,
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
            "value": 229.1694564746649,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 317.965971760259,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 339.67668036893883,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz latency_p50",
            "value": 45.710672736731794,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz latency_p95",
            "value": 66.88567810897439,
            "unit": "us"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz latency_p99",
            "value": 78.82924256819024,
            "unit": "us"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz time_per_sample",
            "value": 2001.33422281521,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 105.8687232102784,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 233.93494689116778,
            "unit": "us"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 278.40118173116934,
            "unit": "us"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "dev@zeyus.com",
            "name": "zeyus",
            "username": "zeyus"
          },
          "committer": {
            "email": "dev@zeyus.com",
            "name": "zeyus",
            "username": "zeyus"
          },
          "distinct": true,
          "id": "727ae37222dd70ba3cea152aa6693733edb1983a",
          "message": "[liblsl_test] migrate macos flutter files. Build all apps.",
          "timestamp": "2026-10-08T16:13:35+02:00",
          "tree_id": "1521999c52f3f00dc41b34cd3aecd5f12136545b",
          "url": "https://github.com/NexusDynamic/liblsl.dart/commit/727ae37222dd70ba3cea152aa6693733edb1983a"
        },
        "date": 1791469100536,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p50",
            "value": 106.7125577378647,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p95",
            "value": 158.45261634694907,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p99",
            "value": 251.29953942837346,
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
            "value": 128.0064415425386,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 158.33617945304468,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 242.33182813304666,
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
            "value": 71.09521641268657,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p95",
            "value": 83.76448803915082,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p99",
            "value": 97.93515241085515,
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
            "value": 110.0845999815192,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 135.71756147712222,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 160.46975159156318,
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
            "value": 166.25503576506162,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p95",
            "value": 220.63731145749443,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p99",
            "value": 321.2982308582468,
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
            "value": 180.0097131763323,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 215.16024702350478,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 280.2855220238598,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz latency_p50",
            "value": 84.19047009056158,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz latency_p95",
            "value": 98.88371738497881,
            "unit": "us"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz latency_p99",
            "value": 108.36741893172075,
            "unit": "us"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz time_per_sample",
            "value": 2001.33422281521,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 103.27528781317596,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 124.50755940562885,
            "unit": "us"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 146.26152147911853,
            "unit": "us"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "dev@zeyus.com",
            "name": "zeyus",
            "username": "zeyus"
          },
          "committer": {
            "email": "dev@zeyus.com",
            "name": "zeyus",
            "username": "zeyus"
          },
          "distinct": true,
          "id": "128e1aacd20ce275afb7fd31659c47892278a4f5",
          "message": "[chore] update runner actions, add same define to transport_timing",
          "timestamp": "2026-10-08T16:29:32+02:00",
          "tree_id": "235c7087896661354580ff0dad4d7f486af65961",
          "url": "https://github.com/NexusDynamic/liblsl.dart/commit/128e1aacd20ce275afb7fd31659c47892278a4f5"
        },
        "date": 1791469999337,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p50",
            "value": 43.84669426826804,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p95",
            "value": 65.50171656272141,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p99",
            "value": 136.28936085297028,
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
            "value": 95.8843940566112,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 167.00800199487276,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 479.15345891169636,
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
            "value": 32.59516148546027,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p95",
            "value": 54.98462485320488,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p99",
            "value": 169.18809927801703,
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
            "value": 82.07656162539934,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 119.53782041018712,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 186.98933678251706,
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
            "value": 77.8308474309597,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p95",
            "value": 134.24357445046553,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p99",
            "value": 443.82945117149575,
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
            "value": 229.25680070784438,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 323.74445407867825,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 676.3502867670468,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz latency_p50",
            "value": 42.43730444386529,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz latency_p95",
            "value": 75.94247614406413,
            "unit": "us"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz latency_p99",
            "value": 249.36259598007382,
            "unit": "us"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz time_per_sample",
            "value": 2001.33422281521,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 136.64501210541857,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 183.81271968337387,
            "unit": "us"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 211.94680795133536,
            "unit": "us"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "dev@zeyus.com",
            "name": "zeyus",
            "username": "zeyus"
          },
          "committer": {
            "email": "dev@zeyus.com",
            "name": "zeyus",
            "username": "zeyus"
          },
          "distinct": true,
          "id": "22d6a49c88af267ad8f213c4506325b7680e8a2b",
          "message": "match site to global theme",
          "timestamp": "2026-10-09T12:17:28+02:00",
          "tree_id": "4f8d0928200cd9bbc8881da73ddd65255403f3bc",
          "url": "https://github.com/NexusDynamic/liblsl.dart/commit/22d6a49c88af267ad8f213c4506325b7680e8a2b"
        },
        "date": 1791541305246,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p50",
            "value": 104.76929747937902,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p95",
            "value": 124.03465899524235,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p99",
            "value": 201.55642897634607,
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
            "value": 141.5779271383144,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 173.4637614845269,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 218.896860019413,
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
            "value": 67.92219261342325,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p95",
            "value": 85.08595715284173,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p99",
            "value": 107.22153126607736,
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
            "value": 134.4125541891117,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 157.9262890913924,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 176.3785830348752,
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
            "value": 177.95569323197924,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p95",
            "value": 265.2103052582788,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p99",
            "value": 356.03383435045544,
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
            "value": 248.46605339234884,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 282.6652100793581,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 314.66187766682197,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz latency_p50",
            "value": 89.7171976816935,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz latency_p95",
            "value": 101.99710504821269,
            "unit": "us"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz latency_p99",
            "value": 113.45999473633128,
            "unit": "us"
          },
          {
            "name": "eventStream/pushSample/8ch@500Hz time_per_sample",
            "value": 2001.33422281521,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 131.18856816163316,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 155.1130585539795,
            "unit": "us"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 171.5458604962805,
            "unit": "us"
          },
          {
            "name": "eventStream/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          }
        ]
      }
    ]
  }
}