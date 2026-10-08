plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.30.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# Bewusst aus: Der PoC wird am selben Tag auf- und abgebaut (Entscheidung D3). Im Echtbetrieb
# für State-Storage, Key Vaults und Daten-Storage wieder einschalten.
rule "azurerm_resources_missing_prevent_destroy" {
  enabled = false
}
