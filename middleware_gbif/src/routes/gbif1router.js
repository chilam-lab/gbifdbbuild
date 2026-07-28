var debug = require('debug')('verbs:router')
var router = require('express').Router()
var gbifCtrl = require('../controllers/gbif1_controller')
var verbUtils = require('../controllers/verb_utils')

router.all('/', function (req, res) {
  res.json({
    data: {
      message: '¡Yey! Bienvenido al API de GBIF V1'
    }
  })
})

router.all('/db-health', async (req, res) => {
  try {
    await verbUtils.pool.one('SELECT 1 AS status')
    res.status(200).json({
      status: 'UP',
      message: 'database connected',
      timestamp: new Date().toISOString()
    })
  } catch (error) {
    debug(error)
    res.status(503).json({
      status: 'DOWN',
      message: 'database unreachable',
      error: error.message
    })
  }
})

router.route('/variables')
  .get(gbifCtrl.variables)
  .post(gbifCtrl.variables)

router.route('/secuencia')
  .get(gbifCtrl.secuencia)
  .post(gbifCtrl.secuencia)

router.route('/variables/:id')
  .get(gbifCtrl.get_variable_byid)
  .post(gbifCtrl.get_variable_byid)

router.route('/get-data/:id')
  .get(gbifCtrl.get_data_byid)
  .post(gbifCtrl.get_data_byid)

router.route('/info')
  .get(gbifCtrl.get_sourceinfo)
  .post(gbifCtrl.get_sourceinfo)

module.exports = router;
