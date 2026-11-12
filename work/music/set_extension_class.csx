// Android: route the GameMusicEmu extension to the Java class and add the
// (zlib goes through GameMusicEmu_Read, see bufferInflate patch).
uint maxId = 0;
foreach (var ext in Data.Extensions)
    foreach (var file in ext.Files)
        foreach (var fn in file.Functions)
            if (fn.ID > maxId) maxId = fn.ID;

foreach (var ext in Data.Extensions)
{
    if (ext.Name.Content != "GameMusicEmu")
        continue;
    ext.ClassName = Data.Strings.MakeString("GameMusicEmu");
    var file = ext.Files[0];
    var template = file.Functions[0];
    Console.WriteLine("ClassName set: " + ext.ClassName.Content);
}
