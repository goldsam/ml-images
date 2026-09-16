using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;

namespace OnnxSmoke;

/// <summary>
/// Loads the ONNX model exported by smoke/export and checks it computes
/// y = 2x + 1. Tries the CUDA execution provider first and falls back to CPU,
/// so the same binary is meaningful on a machine without a GPU.
/// </summary>
internal static class Program
{
    private static readonly float[] Input = [1f, 2f, 3f, 4f];
    private static readonly float[] Expected = [3f, 5f, 7f, 9f];

    private static int Main(string[] args)
    {
        var modelPath = args.Length > 0 ? args[0] : "model.onnx";
        var requireGpu = Environment.GetEnvironmentVariable("REQUIRE_GPU") == "1";

        if (!File.Exists(modelPath))
        {
            Console.Error.WriteLine($"ERROR: model not found: {modelPath}");
            return 1;
        }

        Console.WriteLine($"ONNX Runtime {typeof(InferenceSession).Assembly.GetName().Version}");
        Console.WriteLine($"model: {modelPath} ({new FileInfo(modelPath).Length} bytes)");

        InferenceSession session;
        string provider;
        try
        {
            using var options = new SessionOptions();
            options.AppendExecutionProvider_CUDA(0);
            session = new InferenceSession(modelPath, options);
            provider = "CUDA";
        }
        catch (Exception ex)
        {
            if (requireGpu)
            {
                Console.Error.WriteLine($"ERROR: CUDA provider required but unavailable: {ex.Message}");
                return 1;
            }

            Console.WriteLine($"CUDA provider unavailable ({ex.GetType().Name}), falling back to CPU");
            session = new InferenceSession(modelPath);
            provider = "CPU";
        }

        using (session)
        {
            Console.WriteLine($"execution provider: {provider}");

            var inputName = session.InputMetadata.Keys.First();
            var tensor = new DenseTensor<float>(Input, [1, Input.Length]);
            using var results = session.Run([NamedOnnxValue.CreateFromTensor(inputName, tensor)]);

            var output = results.First().AsEnumerable<float>().ToArray();
            Console.WriteLine($"input : [{string.Join(", ", Input)}]");
            Console.WriteLine($"output: [{string.Join(", ", output)}]");

            if (output.Length != Expected.Length)
            {
                Console.Error.WriteLine($"ERROR: expected {Expected.Length} values, got {output.Length}");
                return 1;
            }

            for (var i = 0; i < Expected.Length; i++)
            {
                if (Math.Abs(output[i] - Expected[i]) > 1e-4f)
                {
                    Console.Error.WriteLine(
                        $"ERROR: index {i}: expected {Expected[i]}, got {output[i]}");
                    return 1;
                }
            }
        }

        Console.WriteLine($"OK: y = 2x + 1 verified on {provider}");
        return 0;
    }
}
