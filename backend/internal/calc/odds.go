package calc

type OddsConfig struct {
	BaseOdds       int
	BaseRolls      int
	CharmRolls     int
	HasShinyCharm  bool
	AvgTimeSeconds int
}

func CalculateEstimatedTimeHours(c OddsConfig) float64 {
	totalRolls := c.BaseRolls
	if c.HasShinyCharm {
		totalRolls += c.CharmRolls
	}
	if totalRolls <= 0 {
		totalRolls = 1
	}

	expectedEncounters := float64(c.BaseOdds) / float64(totalRolls)
	ettsSeconds := expectedEncounters * float64(c.AvgTimeSeconds)
	return ettsSeconds / 3600.0
}
