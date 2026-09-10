import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:onnxruntime_v2/onnxruntime_v2.dart';

void main() {
  test('Test ONNX providers', () async {
    final modelPath = 'assets/models/fastconformer_full_mixed.onnx';
    final modelFile = File(modelPath);

    final bytes = await modelFile.readAsBytes();

    OrtEnv.instance.init();

    // Test 1: Plain default options (no providers added)
    final opt1 = OrtSessionOptions();
    try {
      final s1 = OrtSession.fromBuffer(bytes, opt1);
      print('TEST 1 (No provider added): SUCCESS!');
      s1.release();
    } catch (e) {
      print('TEST 1 (No provider added): FAILED: $e');
    }
    opt1.release();

    // Test 2: CPU provider with useNone
    final opt2 = OrtSessionOptions();
    try {
      opt2.appendCPUProvider(CPUFlags.useNone);
      final s2 = OrtSession.fromBuffer(bytes, opt2);
      print('TEST 2 (CPU useNone): SUCCESS!');
      s2.release();
    } catch (e) {
      print('TEST 2 (CPU useNone): FAILED: $e');
    }
    opt2.release();

    // Test 3: Set intra/inter op threads
    final opt3 = OrtSessionOptions();
    try {
      opt3.setIntraOpNumThreads(2);
      opt3.setInterOpNumThreads(1);
      final s3 = OrtSession.fromBuffer(bytes, opt3);
      print('TEST 3 (Threads set): SUCCESS!');
      s3.release();
    } catch (e) {
      print('TEST 3 (Threads set): FAILED: $e');
    }
    opt3.release();

    final sessionOptions2 = OrtSessionOptions();
    try {
      sessionOptions2.appendXnnpackProvider();
      final session2 = OrtSession.fromBuffer(bytes, sessionOptions2);
      print('Loaded with XNNPACK Provider!');
      session2.release();
    } catch (e) {
      print('Error with XNNPACK: $e');
    }

    final sessionOptions3 = OrtSessionOptions();
    try {
      final success = sessionOptions3.appendDirectMLProvider();
      print('DirectML append returned: $success');
      final session3 = OrtSession.fromBuffer(bytes, sessionOptions3);
      print('Loaded with DirectML Provider!');
      session3.release();
    } catch (e) {
      print('Error with DirectML: $e');
    }
    sessionOptions3.release();

    final sessionOptions4 = OrtSessionOptions();
    try {
      await sessionOptions4.appendDefaultProviders();
      final session4 = OrtSession.fromBuffer(bytes, sessionOptions4);
      print('Loaded with appendDefaultProviders()!');
      print('Input names: ${session4.inputNames}');
      print('Output names: ${session4.outputNames}');

      // Test 1 second of dummy audio (16000 samples)
      final numSamples = 16000;
      final audioSignal = Float32List(numSamples);
      final audioTensor = OrtValueTensor.createTensorWithDataList(audioSignal, [1, numSamples]);
      final lengthTensor = OrtValueTensor.createTensorWithDataList(Int64List.fromList([numSamples]), [1]);
      
      final runOptions = OrtRunOptions();
      final inputs = {
        session4.inputNames[0]: audioTensor,
        session4.inputNames[1]: lengthTensor,
      };
      
      final outputs = await session4.runAsync(runOptions, inputs);
      print('Outputs count: ${outputs?.length}');
      if (outputs != null && outputs.isNotEmpty) {
        final val = outputs[0]?.value;
        print('Output 0 type: ${val.runtimeType}');
        if (val is List) {
          print('Output 0 outer length: ${val.length}');
          if (val.isNotEmpty && val[0] is List) {
            final l1 = val[0] as List;
            print('Output 0 l1 length: ${l1.length}');
            if (l1.isNotEmpty && l1[0] is List) {
              final l2 = l1[0] as List;
              print('Output 0 l2 length (vocab dim): ${l2.length}');
            }
          }
        }
      }
      
      audioTensor.release();
      lengthTensor.release();
      runOptions.release();
      outputs?.forEach((o) => o?.release());
      session4.release();
    } catch (e, st) {
      print('Error with appendDefaultProviders: $e\n$st');
    }
    sessionOptions4.release();

    sessionOptions2.release();
    OrtEnv.instance.release();
  });
}
