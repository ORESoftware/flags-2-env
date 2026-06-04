using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace OreSoftware.Flags2Env
{
    public sealed class Flags2Env : IDisposable
    {
        private readonly IntPtr _handle;
        private readonly ParseFromFileDelegate _parseFromFile;
        private readonly ParseDelegate _parse;
        private readonly ParseProcessFromFileDelegate _parseProcessFromFile;
        private readonly ParseProcessDelegate _parseProcess;
        private readonly FreeDelegate _free;

        public Flags2Env(string? libraryPath = null)
        {
            _handle = NativeLibrary.Load(libraryPath ?? DefaultLibraryName());
            _parseFromFile = Load<ParseFromFileDelegate>("f2e_parse_json_argv_from_file");
            _parse = Load<ParseDelegate>("f2e_parse_json_argv");
            _parseProcessFromFile = Load<ParseProcessFromFileDelegate>("f2e_parse_process_from_file");
            _parseProcess = Load<ParseProcessDelegate>("f2e_parse_process");
            _free = Load<FreeDelegate>("f2e_free");
        }

        public IReadOnlyDictionary<string, string> Parse(IEnumerable<string> argv, string? configPath = null)
        {
            string argvJson = JsonSerializer.Serialize(argv);
            IntPtr argvPtr = Utf8(argvJson);
            IntPtr configPtr = IntPtr.Zero;
            IntPtr result = IntPtr.Zero;
            try
            {
                if (configPath == null)
                {
                    result = _parse(argvPtr);
                }
                else
                {
                    configPtr = Utf8(configPath);
                    result = _parseFromFile(configPtr, argvPtr);
                }
                return DecodeMap(result);
            }
            finally
            {
                if (result != IntPtr.Zero) _free(result);
                if (configPtr != IntPtr.Zero) Marshal.FreeCoTaskMem(configPtr);
                Marshal.FreeCoTaskMem(argvPtr);
            }
        }

        public IReadOnlyDictionary<string, string> ParseProcess(string? configPath = null)
        {
            IntPtr configPtr = IntPtr.Zero;
            IntPtr result = IntPtr.Zero;
            try
            {
                if (configPath == null)
                {
                    result = _parseProcess();
                }
                else
                {
                    configPtr = Utf8(configPath);
                    result = _parseProcessFromFile(configPtr);
                }
                return DecodeMap(result);
            }
            finally
            {
                if (result != IntPtr.Zero) _free(result);
                if (configPtr != IntPtr.Zero) Marshal.FreeCoTaskMem(configPtr);
            }
        }

        public Dictionary<string, string> Apply(IDictionary<string, string> env, IEnumerable<string> argv, string? configPath = null)
        {
            var combined = new Dictionary<string, string>(env);
            foreach (var pair in Parse(argv, configPath))
            {
                combined[pair.Key] = pair.Value;
            }
            return combined;
        }

        public void Dispose()
        {
            NativeLibrary.Free(_handle);
        }

        private T Load<T>(string name) where T : Delegate
        {
            return Marshal.GetDelegateForFunctionPointer<T>(NativeLibrary.GetExport(_handle, name));
        }

        private static IntPtr Utf8(string value)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(value + "\0");
            IntPtr ptr = Marshal.AllocCoTaskMem(bytes.Length);
            Marshal.Copy(bytes, 0, ptr, bytes.Length);
            return ptr;
        }

        private static IReadOnlyDictionary<string, string> DecodeMap(IntPtr result)
        {
            if (result == IntPtr.Zero) return new Dictionary<string, string>();
            string json = Marshal.PtrToStringUTF8(result) ?? "{}";
            return JsonSerializer.Deserialize<Dictionary<string, string>>(json) ?? new Dictionary<string, string>();
        }

        private static string DefaultLibraryName()
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX)) return "libflags2env.dylib";
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) return "flags2env.dll";
            return "libflags2env.so";
        }

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate IntPtr ParseFromFileDelegate(IntPtr configPath, IntPtr argvJson);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate IntPtr ParseDelegate(IntPtr argvJson);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate IntPtr ParseProcessFromFileDelegate(IntPtr configPath);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate IntPtr ParseProcessDelegate();

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate void FreeDelegate(IntPtr value);
    }
}
