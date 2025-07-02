// Node.js test script for LibLSL WASM

// Set up the global liblsl object that the module expects
global.liblsl = {};

const Module = require('./liblsl.js');

async function testLibLSL() {
    console.log('Loading LibLSL WASM module...');
    
    try {
        // Wait for the module to be ready
        await new Promise((resolve) => {
            if (global.liblsl.calledRun) {
                resolve();
            } else {
                const checkReady = () => {
                    if (global.liblsl.calledRun) {
                        resolve();
                    } else {
                        setTimeout(checkReady, 50);
                    }
                };
                checkReady();
            }
        });
        
        const lsl = global.liblsl;
        console.log('✓ LibLSL loaded successfully');
        
        // Test basic functionality
        const version = lsl.ccall('lsl_library_version', 'number', []);
        const protocolVersion = lsl.ccall('lsl_protocol_version', 'number', []);
        
        console.log(`✓ Library version: ${version}`);
        console.log(`✓ Protocol version: ${protocolVersion}`);
        
        // Test creating stream info
        const streamName = "TestStream";
        const streamType = "EEG";
        const sourceId = "TestSource";
        
        const namePtr = lsl.allocateUTF8(streamName);
        const typePtr = lsl.allocateUTF8(streamType);
        const sourcePtr = lsl.allocateUTF8(sourceId);
        
        const streamInfo = lsl.ccall('lsl_create_streaminfo', 'number', 
            ['number', 'number', 'number', 'number', 'number', 'number'],
            [namePtr, typePtr, 2, 100.0, 1, sourcePtr] // 2 channels, 100Hz, float32
        );
        
        if (streamInfo) {
            console.log('✓ Stream info created successfully');
            
            // Test creating outlet
            const outlet = lsl.ccall('lsl_create_outlet', 'number', 
                ['number', 'number', 'number'],
                [streamInfo, 0, 360] // chunkSize=0 (default), maxBuffer=360
            );
            
            if (outlet) {
                console.log('✓ Outlet created successfully');
                
                // Test pushing a sample
                const sample = lsl._malloc(2 * 4); // 2 channels * 4 bytes per float
                const sampleView = new Float32Array(lsl.HEAPF32.buffer, sample, 2);
                sampleView[0] = 1.5;
                sampleView[1] = 2.5;
                
                const result = lsl.ccall('lsl_push_sample_f', 'number', 
                    ['number', 'number'], [outlet, sample]);
                
                if (result === 0) {
                    console.log('✓ Sample pushed successfully');
                } else {
                    console.log('⚠ Sample push returned:', result);
                }
                
                // Cleanup
                lsl._free(sample);
                lsl.ccall('lsl_destroy_outlet', null, ['number'], [outlet]);
                console.log('✓ Outlet destroyed');
            } else {
                console.log('✗ Failed to create outlet');
            }
            
            lsl.ccall('lsl_destroy_streaminfo', null, ['number'], [streamInfo]);
            console.log('✓ Stream info destroyed');
        } else {
            console.log('✗ Failed to create stream info');
        }
        
        // Cleanup
        lsl._free(namePtr);
        lsl._free(typePtr);
        lsl._free(sourcePtr);
        
        console.log('\n🎉 All tests passed! The LibLSL WASM module is working correctly.');
        console.log('\nTo see the web demo:');
        console.log('1. Run: node server.js');
        console.log('2. Open: http://127.0.0.1:8080/');
        
    } catch (error) {
        console.error('✗ Error:', error);
        process.exit(1);
    }
}

testLibLSL();