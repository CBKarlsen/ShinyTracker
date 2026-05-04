import React, { useEffect, useState } from 'react';
import { Typography, Grid, Card, CardContent, LinearProgress, Box, CircularProgress } from '@mui/material';
import { useAuth } from '../context/AuthContext';

interface Hunt {
  id: string;
  encounter_id: number;
  encounter_count: number;
  status: string;
  hunt_parameters: any;
}

const Dashboard: React.FC = () => {
  const { token } = useAuth();
  const [hunts, setHunts] = useState<Hunt[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchHunts = async () => {
      try {
        const res = await fetch('http://localhost:8080/api/hunts', {
          headers: { Authorization: `Bearer ${token}` }
        });
        if (res.ok) {
          const data = await res.json() || [];
          setHunts(data);
        }
      } catch (err) {
        console.error(err);
      } finally {
        setLoading(false);
      }
    };
    fetchHunts();
  }, [token]);

  if (loading) return <CircularProgress />;

  return (
    <Box>
      <Typography variant="h4" gutterBottom>Active Hunts</Typography>
      <Grid container spacing={3}>
        {hunts.length === 0 ? (
          <Grid item xs={12}>
            <Typography variant="body1" color="text.secondary">No active hunts yet. Click 'New Hunt' to start!</Typography>
          </Grid>
        ) : hunts.map(hunt => (
          <Grid item xs={12} sm={6} md={4} key={hunt.id}>
            <Card>
              <CardContent>
                <Typography variant="h6" color="primary">Hunt #{hunt.id.substring(0,6)}</Typography>
                <Typography variant="body2" color="text.secondary">
                  Encounter ID: {hunt.encounter_id}
                </Typography>
                <Box sx={{ mt: 2, mb: 1 }}>
                  <Typography variant="body1">Encounters: {hunt.encounter_count}</Typography>
                </Box>
                <Box sx={{ display: 'flex', alignItems: 'center' }}>
                  <Box sx={{ width: '100%', mr: 1 }}>
                    <LinearProgress variant="determinate" value={Math.min((hunt.encounter_count / 4096) * 100, 100)} color="secondary" />
                  </Box>
                  <Box sx={{ minWidth: 35 }}>
                    <Typography variant="body2" color="text.secondary">
                      {Math.min((hunt.encounter_count / 4096) * 100, 100).toFixed(1)}%
                    </Typography>
                  </Box>
                </Box>
              </CardContent>
            </Card>
          </Grid>
        ))}
      </Grid>
    </Box>
  );
};

export default Dashboard;
