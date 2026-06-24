using UndertaleModLib.Models;
using System;

foreach (var ext in Data.Extensions)
{
    if (ext.Name?.Content == "Steamworks")
    {
        ext.ClassName = Data.Strings.MakeString("Steamworks");
        Console.WriteLine($"Set Steamworks extension class to {ext.ClassName.Content}");
    }
}
