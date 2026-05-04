import React, { useState, useEffect } from 'react';
import { Modal, Box, Typography, Button, TextField, Autocomplete, CircularProgress, FormControl, InputLabel, Select, MenuItem } from '@mui/material';
import { motion } from 'framer-motion';
import { useAuth } from '../context/AuthContext';

const style = {
  position: 'absolute' as 'absolute',
  top: '50%',
  left: '50%',
  transform: 'translate(-50%, -50%)',
  width: 500,
  bgcolor: 'background.paper',
  borderRadius: 4,
  boxShadow: 24,
  p: 4,
};

interface Pokemon {
  id: number;
  name: string;
}

interface Recommendation {
  encounter_id: number;
  game_title: string;
  method_name: string;
  estimated_time_hours: number;
}

interface Props {
  open: boolean;
  onClose: () => void;
}

const NewHuntModal: React.FC<Props> = ({ open, onClose }) => {
  const { token } = useAuth();
  const [options, setOptions] = useState<Pokemon[]>([]);
  const [selected, setSelected] = useState<Pokemon | null>(null);
  const [recommendations, setRecommendations] = useState<Recommendation[]>([]);
  const [selectedEncounterId, setSelectedEncounterId] = useState<number | ''>('');
  const [loadingSearch, setLoadingSearch] = useState(false);
  const [loadingRec, setLoadingRec] = useState(false);
  const [search, setSearch] = useState('');

  useEffect(() => {
    if (!open) {
      setSelected(null);
      setRecommendations([]);
      setSelectedEncounterId('');
      setSearch('');
      return;
    }
  }, [open]);

  useEffect(() => {
    const fetchSearch = async () => {
      setLoadingSearch(true);
      try {
        const res = await fetch(`http://localhost:8080/api/pokemon?q=${search}`);
        if (res.ok) setOptions(await res.json() || []);
      } catch (err) {
        console.error(err);
      } finally {
        setLoadingSearch(false);
      }
    };
    const timer = setTimeout(fetchSearch, 300);
    return () => clearTimeout(timer);
  }, [search]);

  useEffect(() => {
    if (!selected) {
      setRecommendations([]);
      setSelectedEncounterId('');
      return;
    }
    const fetchRec = async () => {
      setLoadingRec(true);
      try {
        const res = await fetch(`http://localhost:8080/api/recommend/${selected.id}`, {
          headers: { Authorization: `Bearer ${token}` }
        });
        if (res.ok) {
          const recs = await res.json() || [];
          setRecommendations(recs);
          if (recs.length > 0) {
            setSelectedEncounterId(recs[0].encounter_id);
          } else {
            setSelectedEncounterId('');
          }
        }
      } catch (err) {
        console.error(err);
      } finally {
        setLoadingRec(false);
      }
    };
    fetchRec();
  }, [selected, token]);

  const handleStart = async () => {
    if (!selectedEncounterId) return;
    try {
      const res = await fetch('http://localhost:8080/api/hunts', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`
        },
        body: JSON.stringify({
          encounter_id: selectedEncounterId,
          hunt_parameters: {}
        })
      });
      if (res.ok) {
        onClose();
        window.location.reload(); 
      }
    } catch (err) {
      console.error(err);
    }
  };

  return (
    <Modal open={open} onClose={onClose}>
      <Box sx={style} component={motion.div} initial={{ opacity: 0, scale: 0.9 }} animate={{ opacity: 1, scale: 1 }}>
        <Typography variant="h5" gutterBottom>Start a New Hunt</Typography>
        
        <Autocomplete
          options={options}
          getOptionLabel={(option) => option.name}
          onChange={(_, value) => setSelected(value)}
          onInputChange={(_, value) => setSearch(value)}
          renderInput={(params) => (
            <TextField 
              {...params} 
              label="Search Pokémon" 
              variant="outlined" 
              margin="normal"
              InputProps={{
                ...params.InputProps,
                endAdornment: (
                  <React.Fragment>
                    {loadingSearch ? <CircularProgress color="inherit" size={20} /> : null}
                    {params.InputProps?.endAdornment}
                  </React.Fragment>
                ),
              }}
            />
          )}
        />

        {loadingRec && <Box sx={{ mt: 2 }}><CircularProgress size={24} /></Box>}

        {recommendations.length > 0 && !loadingRec && (
          <Box sx={{ mt: 2 }}>
            <FormControl fullWidth margin="normal">
              <InputLabel id="encounter-select-label">Choose Hunting Method</InputLabel>
              <Select
                labelId="encounter-select-label"
                value={selectedEncounterId}
                label="Choose Hunting Method"
                onChange={(e) => setSelectedEncounterId(e.target.value as number)}
              >
                {recommendations.map((rec) => (
                  <MenuItem key={rec.encounter_id} value={rec.encounter_id}>
                    {rec.game_title} - {rec.method_name} (ETTS: {rec.estimated_time_hours.toFixed(1)}h)
                  </MenuItem>
                ))}
              </Select>
            </FormControl>
          </Box>
        )}
        
        {selected && recommendations.length === 0 && !loadingRec && (
          <Box sx={{ mt: 2 }}><Typography color="error" variant="body2">No encounter data for this Pokémon based on your owned games.</Typography></Box>
        )}

        <Box sx={{ mt: 3, display: 'flex', justifyContent: 'flex-end', gap: 2 }}>
          <Button onClick={onClose} color="inherit">Cancel</Button>
          <Button variant="contained" color="primary" onClick={handleStart} disabled={!selectedEncounterId}>Start Hunt</Button>
        </Box>
      </Box>
    </Modal>
  );
};

export default NewHuntModal;
