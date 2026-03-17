
/**
 * Express router que monta las funciones asociadas a redes. 
 * @type {object}
 * @const
 * @namespace netRouter
 */
var router = require('express').Router()
var regionCtrl = require('../controllers/gbif1_controller')

router.all('/', function(req, res) {
  res.json({ 
    data: { 
      message: '¡Yey! Bienvenido al API de GBIF-SPECIES V1'
    }
  })
})

router.route('/variables')
  .get(regionCtrl.variables)
  .post(regionCtrl.variables)

router.route('/variables/:id')
  .get(regionCtrl.get_variable_byid)
  .post(regionCtrl.get_variable_byid)

router.route('/get-data/:id')
  .get(regionCtrl.get_data_byid)
  .post(regionCtrl.get_data_byid)

module.exports = router;