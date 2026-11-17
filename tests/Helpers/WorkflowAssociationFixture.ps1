# Stand-ins for a SharePoint workflow association: real .NET objects, as SharePoint gives, and not custom objects. PowerShell turns an
# exception of a .NET getter into $null, so only a compiled class can show what the code does with a getter that fails, and how often
# it reads one. The code is C# 5, so that Windows PowerShell 5.1 can compile it.
if (-not ('SPSTestWorkflowAssociation' -as [type])) {
    Add-Type -TypeDefinition @'
public class SPSTestWorkflowAssociation
{
    private int running;
    private int reads;

    public string Name { get; set; }

    // The first read gives the number that was set and each read after it gives one more, so that a second read of the counter shows.
    public int RunningInstances
    {
        get { int value = running + reads; reads++; return value; }
        set { running = value; }
    }

    // How many times the running instances were read.
    public int Reads { get { return reads; } }
}

public class SPSTestUnnamedWorkflowAssociation
{
    public int RunningInstances { get { return 4; } }

    public string Name { get { throw new System.InvalidOperationException("The name could not be read."); } }
}
'@
}
